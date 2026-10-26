import AppKit

/// Gives each app on screen a plate color taken from its own icon. An app keeps its color while it
/// runs, and two apps on screen get colors that look different whenever their icons allow it.
@MainActor
final class PlateColors {
    private let icon: (pid_t) -> NSImage?
    private var iconColorCache: [pid_t: [NSColor]] = [:]
    /// The color each running app uses: one of its icon's colors, or a shade of one.
    private var chosen: [pid_t: NSColor] = [:]

    init(icon: @escaping (pid_t) -> NSImage?) {
        self.icon = icon
    }

    func color(for pid: pid_t) -> NSColor {
        chosen[pid] ?? iconColors(for: pid).first ?? .controlAccentColor
    }

    func assign(to pids: Set<pid_t>) {
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        chosen = Self.assign(
            pids.map { (pid: $0, colors: iconColors(for: $0)) },
            keeping: chosen.filter { running.contains($0.key) })
    }

    /// Each app gets the strongest of its icon's colors, unless another app on screen already looks like
    /// that, then its next one, then a darker or lighter shade of them. Apps with fewer colors choose
    /// first, having less to fall back on; launch order breaks ties. Colors in `kept` stay when still free.
    nonisolated static func assign(
        _ apps: [(pid: pid_t, colors: [NSColor])],
        keeping kept: [pid_t: NSColor]
    ) -> [pid_t: NSColor] {
        var chosen = kept
        var taken: [NSColor] = []
        for app in apps.sorted(by: { ($0.colors.count, $0.pid) < ($1.colors.count, $1.pid) }) {
            guard let strongest = app.colors.first else { continue }
            let isFree = { (color: NSColor) in !taken.contains { areAlike($0, color) } }
            let options = app.colors + app.colors.map(darker) + app.colors.map(lighter)
            let color = chosen[app.pid].flatMap { isFree($0) ? $0 : nil } ?? options.first(where: isFree) ?? strongest
            chosen[app.pid] = color
            taken.append(color)
        }
        return chosen
    }

    /// Whether two plates would be hard to tell apart: colors by hue and lightness, grays by lightness.
    nonisolated static func areAlike(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB), isGray(a) == isGray(b)
        else { return false }
        let lightness = abs(a.brightnessComponent - b.brightnessComponent)
        if isGray(a) { return lightness < 0.25 }
        let hues = abs(a.hueComponent - b.hueComponent)
        return min(hues, 1 - hues) < 0.06 && lightness < 0.3
    }

    /// An icon's own colors, biggest first: its real colors, or only for icons without any (ChatGPT,
    /// Cursor), its black and grays. White and off-white are left out, as they're the background of so
    /// many icons.
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
        // Colorful pixels go into 12 hue buckets, the rest into black, dark gray and gray. A bucket's
        // average color counts if the bucket is big enough.
        var buckets: [Int: (count: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat)] = [:]
        for x in 0..<side {
            for y in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5
                else { continue }
                let (saturation, brightness) = (color.saturationComponent, color.brightnessComponent)
                if brightness > 0.82, saturation < 0.15 { continue }  // white and off-white
                let key =
                    saturation < 0.18 || brightness < 0.2
                    ? 12 + min(2, Int(brightness * 3)) : min(11, Int(color.hueComponent * 12))
                var bucket = buckets[key] ?? (0, 0, 0, 0)
                bucket.count += 1
                bucket.red += color.redComponent
                bucket.green += color.greenComponent
                bucket.blue += color.blueComponent
                buckets[key] = bucket
            }
        }
        let total = buckets.values.reduce(0) { $0 + $1.count }
        let biggestColor = buckets.filter { $0.key < 12 }.map(\.value.count).max() ?? 0
        let biggestGray = buckets.filter { $0.key >= 12 }.map(\.value.count).max() ?? 0
        // A color must cover a real part of the icon, not just a small accent.
        let colored = buckets.filter { $0.key < 12 && $0.value.count >= max(8, total * 0.05, biggestColor * 0.2) }
        let grays = buckets.filter { $0.key >= 12 && $0.value.count >= max(8, biggestGray * 0.2) }
        func averages(_ part: [Int: (count: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat)]) -> [NSColor] {
            part.sorted { ($0.value.count, -$0.key) > ($1.value.count, -$1.key) }
                .map {
                    NSColor(
                        srgbRed: $0.value.red / $0.value.count, green: $0.value.green / $0.value.count,
                        blue: $0.value.blue / $0.value.count, alpha: 1)
                }
        }
        return colored.isEmpty ? averages(grays) : averages(colored)
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

    private nonisolated static func isGray(_ color: NSColor) -> Bool {
        (color.usingColorSpace(.sRGB)?.saturationComponent ?? 0) < 0.18
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

    init(tint: NSColor, isDark: Bool) {
        let rgb = tint.usingColorSpace(.sRGB) ?? tint
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        // Dark icon colors, like ChatGPT's black, become smoked glass rather than a washed-out gray.
        tintAlpha = luminance < 0.3 ? 0.85 : (isDark ? 0.5 : 0.45)
        let base: CGFloat = isDark ? 0.15 : 0.95
        wantsLightText = base * (1 - tintAlpha) + luminance * tintAlpha < 0.5
    }
}
