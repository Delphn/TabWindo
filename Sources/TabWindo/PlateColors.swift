import AppKit

/// Gives each app on screen a plate color taken from its own icon, with a calmer one for dark mode. An app keeps its
/// colors while it runs, and two apps on screen get colors that look different whenever their icons allow it.
@MainActor
final class PlateColors {
    private let icon: (pid_t) -> NSImage?
    private var iconColorCache: [pid_t: [NSColor]] = [:]
    /// The colors running apps use: one of their icon's colors, or a shade of one, and its dark mode tone.
    private var chosenLight: [pid_t: NSColor] = [:]
    private var chosenDark: [pid_t: NSColor] = [:]

    init(icon: @escaping (pid_t) -> NSImage?) {
        self.icon = icon
    }

    /// A dynamic color, so plates follow the Mac between light and dark on their own.
    func color(for pid: pid_t) -> NSColor {
        let light = chosenLight[pid] ?? iconColors(for: pid).first ?? .controlAccentColor
        return Self.plateColor(light: light, dark: chosenDark[pid] ?? Self.darkTone(light))
    }

    func assign(to pids: Set<pid_t>) {
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let apps = pids.map { (pid: $0, colors: iconColors(for: $0)) }
        chosenLight = Self.assign(apps, keeping: chosenLight.filter { running.contains($0.key) })
        chosenDark = Self.assign(apps, keeping: chosenDark.filter { running.contains($0.key) }, isDark: true)
    }

    /// A color that is `light` in light mode and `dark` in dark mode.
    nonisolated static func plateColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark : light }
    }

    /// Each app gets the strongest of its icon's colors, unless another app on screen already looks like that, then
    /// its next one, then a darker or lighter shade of them. Apps with fewer colors choose first, having less to fall
    /// back on; launch order breaks ties. Colors in `kept` stay when still free. In dark mode, every color is toned
    /// down first.
    nonisolated static func assign(
        _ apps: [(pid: pid_t, colors: [NSColor])],
        keeping kept: [pid_t: NSColor], isDark: Bool = false
    ) -> [pid_t: NSColor] {
        var chosen = kept
        var taken: [NSColor] = []
        for app in apps.sorted(by: { ($0.colors.count, $0.pid) < ($1.colors.count, $1.pid) }) {
            let colors = isDark ? app.colors.map(darkTone) : app.colors
            guard let strongest = colors.first else { continue }
            let isFree = { (color: NSColor) in !taken.contains { areAlike($0, color) } }
            // Dark tones are deep already, so their shades step lightness by a fixed, visible amount.
            let shades =
                isDark
                ? colors.map { shifted($0, by: -0.12) } + colors.map { shifted($0, by: 0.12) }
                : colors.map(darker) + colors.map(lighter)
            let color =
                chosen[app.pid].flatMap { isFree($0) ? $0 : nil } ?? (colors + shades).first(where: isFree) ?? strongest
            chosen[app.pid] = color
            taken.append(color)
        }
        return chosen
    }

    /// Whether two plates would be hard to tell apart.
    nonisolated static func areAlike(_ a: NSColor, _ b: NSColor) -> Bool {
        OKLCH(a).distance(to: OKLCH(b)) < 0.1
    }

    /// The color a plate takes in dark mode: the same hue, deeper and calmer, so a bright icon color doesn't glare
    /// against the dark panel. Lighter colors stay a little lighter, so colors that differ only in lightness still do.
    nonisolated static func darkTone(_ color: NSColor) -> NSColor {
        var tone = OKLCH(color)
        tone.lightness = 0.3 + 0.2 * tone.lightness
        tone.chroma = min(tone.chroma * 0.7, 0.1)
        return tone.color
    }

    /// An icon's own colors, biggest first: its real colors, or only for icons without any (ChatGPT, Cursor), its
    /// black and grays, or for an all-white icon, its white.
    nonisolated static func colors(of icon: NSImage) -> [NSColor] {
        let side = 32
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        // Colorful pixels go into 12 hue buckets (0–11), the rest into black, dark gray and gray (12–14), and white
        // and off-white, the background of so many icons, into their own (15).
        let white = 15
        var buckets: [Int: Bucket] = [:]
        for x in 0..<side {
            for y in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5
                else { continue }
                let (saturation, brightness) = (color.saturationComponent, color.brightnessComponent)
                let key =
                    if brightness > 0.82, saturation < 0.15 {
                        white
                    } else if saturation < 0.18 || brightness < 0.2 {
                        12 + min(2, Int(brightness * 3))
                    } else {
                        min(11, Int(color.hueComponent * 12))
                    }
                buckets[key, default: Bucket()].add(color, vividness: saturation * brightness)
            }
        }
        let colored = buckets.filter { $0.key < 12 }
        let grays = buckets.filter { (12..<white).contains($0.key) }
        let total = buckets.filter { $0.key != white }.values.reduce(0) { $0 + $1.count }
        // A color must cover a real part of the icon, not just a small accent.
        let biggestColor = colored.values.map(\.count).max() ?? 0
        let real = colored.filter { $0.value.count >= max(8, total / 20, biggestColor / 5) }
        if !real.isEmpty { return biggestFirst(real, vividOnly: true) }
        let biggestGray = grays.values.map(\.count).max() ?? 0
        let shown = grays.filter { $0.value.count >= max(8, biggestGray / 5) }
        if !shown.isEmpty { return biggestFirst(shown, vividOnly: false) }
        guard let whites = buckets[white], whites.count >= 8 else { return [] }
        return [whites.average(vividOnly: false)]
    }

    private nonisolated static func biggestFirst(_ buckets: [Int: Bucket], vividOnly: Bool) -> [NSColor] {
        buckets.sorted { ($0.value.count, -$0.key) > ($1.value.count, -$1.key) }
            .map { $0.value.average(vividOnly: vividOnly) }
    }

    /// The pixels of one color in an icon.
    private struct Bucket {
        private var pixels: [(color: NSColor, vividness: CGFloat)] = []
        var count: Int { pixels.count }

        mutating func add(_ color: NSColor, vividness: CGFloat) {
            pixels.append((color, vividness))
        }

        /// The average color. For a hue, of only its most vivid quarter: the color as the icon draws it, not dimmed by
        /// shading, glows or smoothed edges (Console's yellow, Raycast's neon red).
        func average(vividOnly: Bool) -> NSColor {
            let used =
                vividOnly ? Array(pixels.sorted { $0.vividness > $1.vividness }.prefix(max(1, count / 4))) : pixels
            let sum = used.reduce((red: 0.0, green: 0.0, blue: 0.0)) {
                ($0.red + $1.color.redComponent, $0.green + $1.color.greenComponent, $0.blue + $1.color.blueComponent)
            }
            let n = CGFloat(used.count)
            return NSColor(srgbRed: sum.red / n, green: sum.green / n, blue: sum.blue / n, alpha: 1)
        }
    }

    private nonisolated static func darker(_ color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return NSColor(
            hue: rgb.hueComponent, saturation: rgb.saturationComponent,
            brightness: rgb.brightnessComponent * 0.5, alpha: 1)
    }

    private nonisolated static func lighter(_ color: NSColor) -> NSColor {
        (color.usingColorSpace(.sRGB) ?? color).blended(withFraction: 0.45, of: .white) ?? color
    }

    /// The same color, lighter or darker, kept within what reads well as a dark mode plate.
    private nonisolated static func shifted(_ color: NSColor, by amount: CGFloat) -> NSColor {
        var tone = OKLCH(color)
        tone.lightness = min(max(tone.lightness + amount, 0.2), 0.58)
        return tone.color
    }

    private func iconColors(for pid: pid_t) -> [NSColor] {
        if let known = iconColorCache[pid] { return known }
        let found = icon(pid).map(Self.colors(of:)) ?? []
        iconColorCache[pid] = found
        return found
    }
}

/// How a plate in a given color is drawn, and whether text on it should be white.
struct PlateStyle {
    let tintAlpha: CGFloat
    let wantsLightText: Bool

    /// `tint` is the plate's color as it is in this appearance.
    init(tint: NSColor, isDark: Bool) {
        let rgb = tint.usingColorSpace(.sRGB) ?? tint
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        // Dark mode colors are calm already, so they're drawn nearly solid. In light mode, colors that look dark,
        // like ChatGPT's black, become smoked glass rather than a washed-out gray; the rest stay light.
        tintAlpha = isDark ? 0.9 : OKLCH(rgb).lightness < 0.4 ? 0.85 : 0.45
        let base: CGFloat = isDark ? 0.15 : 0.95
        wantsLightText = base * (1 - tintAlpha) + luminance * tintAlpha < 0.5
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// The color as it is in `appearance`, in sRGB. Plate colors are dynamic: they differ in dark mode.
    func resolved(in appearance: NSAppearance) -> NSColor {
        var resolved = self
        appearance.performAsCurrentDrawingAppearance { resolved = self.usingColorSpace(.sRGB) ?? self }
        return resolved
    }
}
