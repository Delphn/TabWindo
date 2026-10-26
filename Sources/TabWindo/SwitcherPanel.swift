import AppKit

/// Runs one switch, from the first Tab press until the modifier key is released.
@MainActor
final class Switcher {
    /// Latest list from the store, most recent first.
    var windows: [WindowItem] = [] {
        didSet {
            // Lay the panel out once, invisibly, so even the first switch shows it instantly.
            if !isWarmedUp, !windows.isEmpty {
                isWarmedUp = true
                let arrangement = Self.arrange(windows, columns: columns)
                panel.warmUp(windows, layout: arrangement.layout, on: arrangement.screen)
            }
        }
    }
    /// The held modifier; letting go of it confirms the selection.
    var modifier: CGEventFlags = .maskCommand
    /// Windows per row, chosen in the menu bar.
    var columns = AppDelegate.savedColumns
    var onFocus: (@MainActor (WindowItem) -> Void)?
    var onOpenChange: (@MainActor (Bool) -> Void)?

    private let panel = SwitcherPanel()
    private let thumbnails = Thumbnails()
    /// This switch's windows (most recent first), where each one goes, and on which screen.
    private var session: [WindowItem]?
    private var layout: GridLayout?
    private var screen: NSScreen?
    private var selection = 0
    private var wasShiftDown = false
    private var isWarmedUp = false
    private var startedAt: CFTimeInterval = 0
    private var showTimer: Timer?
    private var pollTimer: Timer?

    /// A quick tap switches without ever showing the panel; holding longer than this shows it.
    private let showDelay: TimeInterval = 0.1

    init() {
        panel.onHover = { [unowned self] index in self.select(index) }
        panel.onClick = { [unowned self] index in
            self.select(index)
            self.finish(commit: true)
        }
        thumbnails.onImage = { [unowned self] id, image in
            if self.session != nil { self.panel.setThumbnail(image, for: id) }
        }
    }

    func handle(_ action: Hotkeys.Action) {
        guard session != nil else {
            if action == .next || action == .previous { begin(backwards: action == .previous) }
            return
        }
        switch action {
        case .next: select(selection + 1)
        case .previous: select(selection - 1)
        case .up: select(layout?.neighbor(of: selection, lines: -1) ?? selection)
        case .down: select(layout?.neighbor(of: selection, lines: 1) ?? selection)
        case .confirm: finish(commit: true)
        case .cancel: finish(commit: false)
        }
    }

    #if DEBUG
    /// Opens the panel without a key press and returns its window number, for `--snapshot`.
    func presentForSnapshot() -> Int {
        let arrangement = Self.arrange(windows, columns: columns)
        (session, layout, screen) = (windows, arrangement.layout, arrangement.screen)
        selection = min(1, windows.count - 1)
        showPanel()
        return panel.windowNumber
    }
    #endif

    private func begin(backwards: Bool) {
        guard !windows.isEmpty else { return }
        startedAt = CACurrentMediaTime()
        let arrangement = Self.arrange(windows, columns: columns)
        (session, layout, screen) = (windows, arrangement.layout, arrangement.screen)
        // Start on the previous window, unless the frontmost app has no window at the top of the list.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let next = windows[0].pid == frontPID ? 1 : 0
        selection = backwards ? windows.count - 1 : min(next, windows.count - 1)
        wasShiftDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
        onOpenChange?(true)
        showTimer = schedule(after: showDelay, repeats: false) { $0.showPanel() }
        pollTimer = schedule(after: 1.0 / 120, repeats: true) { $0.pollModifiers() }
        pollModifiers()  // a very quick tap can already be over
    }

    private func select(_ index: Int) {
        guard let session, !session.isEmpty else { return }
        selection = (index % session.count + session.count) % session.count
        if panel.isVisible { panel.select(selection) }
    }

    /// Letting go of the modifier switches; pressing ⇧ on its own steps back.
    private func pollModifiers() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.contains(modifier) else { return finish(commit: true) }
        let isShiftDown = flags.contains(.maskShift)
        if isShiftDown, !wasShiftDown { select(selection - 1) }
        wasShiftDown = isShiftDown
    }

    private func showPanel() {
        guard let session, let layout, let screen else { return }
        let start = CACurrentMediaTime()
        panel.show(session, layout: layout, on: screen, selected: selection, thumbnails: thumbnails.images)
        logger.debug("Panel shown in \(Self.ms(since: start), format: .fixed(precision: 2), privacy: .public) ms, \(Self.ms(since: self.startedAt), format: .fixed(precision: 1), privacy: .public) ms after the key, \(session.count, privacy: .public) windows")
        thumbnails.capture(session, pixelSize: panel.thumbnailPixelSize)
    }

    private func finish(commit: Bool) {
        guard let session else { return }
        self.session = nil
        showTimer?.invalidate()
        pollTimer?.invalidate()
        panel.hide()
        onOpenChange?(false)
        guard commit, session.indices.contains(selection) else { return }
        let item = session[selection]
        // Reorder right away so an immediate second switch already sees the new order.
        windows.removeAll { $0.id == item.id }
        windows.insert(item, at: 0)
        onFocus?(item)
        logger.debug("Switched after \(Self.ms(since: self.startedAt), format: .fixed(precision: 1), privacy: .public) ms")
    }

    /// Lays the windows out for the screen under the pointer.
    private static func arrange(_ windows: [WindowItem], columns: Int) -> (layout: GridLayout, screen: NSScreen) {
        let screen = NSScreen.underPointer
        return (GridLayout(windows, columns: columns, on: screen.visibleFrame), screen)
    }

    private func schedule(after interval: TimeInterval, repeats: Bool,
                          _ action: @escaping @MainActor (Switcher) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private static func ms(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1000
    }
}

private enum Metrics {
    /// A full row spans this share of the screen's width, so fewer windows per row means bigger
    /// previews rather than a narrower panel.
    static let widthShare: CGFloat = 0.7
    /// Past this share of the screen's height, the panel scrolls.
    static let heightShare: CGFloat = 0.9
    static let inset: CGFloat = 16
    static let thumbnailAspect: CGFloat = 16 / 10
    static let tilePadding: CGFloat = 8
    static let titleGap: CGFloat = 6
    static let titleHeight: CGFloat = 16
    static let columnGap: CGFloat = 10
    static let lineGap: CGFloat = 10
}

/// Where each window goes: a fixed number per row, most recent first, simply wrapping. Every window
/// sits on a plate in its app's color, shared with neighbors from the same app.
private struct GridLayout {
    let thumbnail: NSSize
    let frames: [NSRect]
    let plates: [(frame: NSRect, pid: pid_t)]
    let size: NSSize
    /// The tallest the grid gets before the panel scrolls.
    let maxHeight: CGFloat
    private let columns: Int
    private let lineCount: Int

    init(_ windows: [WindowItem], columns: Int, on area: NSRect) {
        let count = windows.count
        let lines = max(1, (count + columns - 1) / columns)
        let gridWidth = area.width * Metrics.widthShare - Metrics.inset * 2
        let cellWidth = ((gridWidth - CGFloat(columns - 1) * Metrics.columnGap) / CGFloat(columns)).rounded(.down)
        thumbnail = NSSize(width: cellWidth - Metrics.tilePadding * 2,
                           height: ((cellWidth - Metrics.tilePadding * 2) / Metrics.thumbnailAspect).rounded())
        let cell = NSSize(width: cellWidth,
                          height: thumbnail.height + Metrics.tilePadding * 2 + Metrics.titleGap + Metrics.titleHeight)
        maxHeight = area.height * Metrics.heightShare - Metrics.inset * 2
        frames = (0..<count).map { index in
            NSRect(x: CGFloat(index % columns) * (cell.width + Metrics.columnGap),
                   y: CGFloat(index / columns) * (cell.height + Metrics.lineGap), width: cell.width, height: cell.height)
        }
        // One plate per run of neighboring windows from the same app on a line.
        var plates: [(frame: NSRect, pid: pid_t)] = []
        var runStart = 0
        for index in windows.indices {
            let isRunEnd = index == count - 1 || windows[index + 1].pid != windows[index].pid
                || (index + 1) % columns == 0
            guard isRunEnd else { continue }
            plates.append((frames[runStart].union(frames[index]), windows[index].pid))
            runStart = index + 1
        }
        self.plates = plates
        self.columns = columns
        lineCount = lines
        let used = CGFloat(min(columns, max(count, 1)))
        size = NSSize(width: used * (cell.width + Metrics.columnGap) - Metrics.columnGap,
                      height: CGFloat(lines) * (cell.height + Metrics.lineGap) - Metrics.lineGap)
    }

    /// The tile in the same column on the line above or below, wrapping around.
    func neighbor(of index: Int, lines step: Int) -> Int {
        guard frames.indices.contains(index), lineCount > 1 else { return index }
        let line = (index / columns + step + lineCount) % lineCount
        return min(line * columns + index % columns, frames.count - 1)
    }
}

/// The Liquid Glass panel. Built once, reused for every switch, and never takes focus from the app
/// behind it.
@MainActor
private final class SwitcherPanel {
    var onHover: (@MainActor (Int) -> Void)?
    var onClick: (@MainActor (Int) -> Void)?
    var isVisible: Bool { window.isVisible }
    #if DEBUG
    var windowNumber: Int { window.windowNumber }
    #endif
    /// The pixel size thumbnails should be captured at for the current layout.
    private(set) var thumbnailPixelSize = CGSize(width: 416, height: 260)

    private let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
    private let glass = NSGlassEffectView()
    private let content = NSView()
    private let scrollView = NSScrollView()
    private let canvas = FlippedView()
    private var plates: [PlateView] = []
    private var tiles: [TileView] = []
    private var icons: [pid_t: NSImage] = [:]
    private var iconColorCache: [pid_t: [NSColor]] = [:]
    /// The color each running app uses: one of its icon's colors, or a shade of one.
    private var chosen: [pid_t: NSColor] = [:]

    init() {
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false

        glass.cornerRadius = 28
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = canvas
        content.addSubview(scrollView)
        glass.contentView = content
        window.contentView = glass
    }

    /// Builds the views, loads icons and creates the window server side once, out of sight.
    func warmUp(_ items: [WindowItem], layout: GridLayout, on screen: NSScreen) {
        window.alphaValue = 0
        show(items, layout: layout, on: screen, selected: 0, thumbnails: [:])
        hide()
        window.alphaValue = 1
    }

    func show(_ items: [WindowItem], layout: GridLayout, on screen: NSScreen, selected: Int,
              thumbnails: [CGWindowID: CGImage]) {
        thumbnailPixelSize = CGSize(width: layout.thumbnail.width * screen.backingScaleFactor,
                                    height: layout.thumbnail.height * screen.backingScaleFactor)
        assignColors(to: Set(items.map(\.pid)))
        let isDark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for (index, plate) in layout.plates.enumerated() {
            let view = plateView(at: index)
            view.frame = plate.frame
            view.tint = color(for: plate.pid)
        }
        plates.dropFirst(layout.plates.count).forEach { $0.isHidden = true }
        for (index, item) in items.enumerated() {
            let tile = tileView(at: index)
            tile.frame = layout.frames[index]
            tile.show(item, index: index, thumbnail: thumbnails[item.id], icon: icon(for: item.pid))
            tile.hasLightTitle = PlateStyle(tint: color(for: item.pid), isDark: isDark).wantsLightText
        }
        tiles.dropFirst(items.count).forEach { $0.isHidden = true }
        canvas.frame = NSRect(origin: .zero, size: layout.size)

        let area = screen.visibleFrame
        let size = NSSize(width: layout.size.width + Metrics.inset * 2,
                          height: min(layout.size.height, layout.maxHeight) + Metrics.inset * 2)
        window.setFrame(NSRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
                               width: size.width, height: size.height), display: false)
        content.frame = glass.bounds
        scrollView.frame = content.bounds.insetBy(dx: Metrics.inset, dy: Metrics.inset)
        scrollView.contentView.scroll(to: .zero)
        select(selected)
        window.orderFrontRegardless()
    }

    func select(_ index: Int) {
        for tile in tiles where !tile.isHidden { tile.isSelected = tile.index == index }
        if tiles.indices.contains(index) { tiles[index].scrollToVisible(tiles[index].bounds) }
    }

    func setThumbnail(_ image: CGImage, for windowID: CGWindowID) {
        tiles.first { !$0.isHidden && $0.windowID == windowID }?.setThumbnail(image)
    }

    func hide() {
        window.orderOut(nil)
    }

    private func plateView(at index: Int) -> PlateView {
        while plates.count <= index {
            let plate = PlateView()
            plates.append(plate)
            canvas.addSubview(plate, positioned: .below, relativeTo: nil)  // always behind the tiles
        }
        plates[index].isHidden = false
        return plates[index]
    }

    private func tileView(at index: Int) -> TileView {
        while tiles.count <= index {
            let tile = TileView()
            tile.onHover = { [unowned self] index in self.onHover?(index) }
            tile.onClick = { [unowned self] index in self.onClick?(index) }
            tiles.append(tile)
            canvas.addSubview(tile)
        }
        tiles[index].isHidden = false
        return tiles[index]
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }

    private func color(for pid: pid_t) -> NSColor {
        chosen[pid] ?? iconColors(for: pid).first ?? .controlAccentColor
    }

    /// Gives each app on screen a color from its own icon: the strongest, unless another app on screen
    /// already looks like that, then its next one, then a darker or lighter shade of them. An app keeps
    /// its color while it runs.
    private func assignColors(to pids: Set<pid_t>) {
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        chosen = chosen.filter { running.contains($0.key) }
        var taken: [NSColor] = []
        // Apps with fewer colors choose first, having less to fall back on; launch order breaks ties.
        for pid in pids.sorted(by: { (iconColors(for: $0).count, $0) < (iconColors(for: $1).count, $1) }) {
            let colors = iconColors(for: pid)
            guard let strongest = colors.first else { continue }
            let isFree = { (color: NSColor) in !taken.contains { Self.areAlike($0, color) } }
            let options = colors + colors.map(Self.darker) + colors.map(Self.lighter)
            let color = chosen[pid].flatMap { isFree($0) ? $0 : nil } ?? options.first(where: isFree) ?? strongest
            chosen[pid] = color
            taken.append(color)
        }
    }

    /// Whether two plates would be hard to tell apart: colors by hue and lightness, grays by lightness.
    private static func areAlike(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB), isGray(a) == isGray(b)
        else { return false }
        let lightness = abs(a.brightnessComponent - b.brightnessComponent)
        if isGray(a) { return lightness < 0.25 }
        let hues = abs(a.hueComponent - b.hueComponent)
        return min(hues, 1 - hues) < 0.06 && lightness < 0.3
    }

    private static func darker(_ color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return NSColor(hue: rgb.hueComponent, saturation: rgb.saturationComponent,
                       brightness: rgb.brightnessComponent * 0.5, alpha: 1)
    }

    private static func lighter(_ color: NSColor) -> NSColor {
        (color.usingColorSpace(.sRGB) ?? color).blended(withFraction: 0.45, of: .white) ?? color
    }

    private static func isGray(_ color: NSColor) -> Bool {
        (color.usingColorSpace(.sRGB)?.saturationComponent ?? 0) < 0.18
    }

    private func iconColors(for pid: pid_t) -> [NSColor] {
        if let known = iconColorCache[pid] { return known }
        let found = icon(for: pid).map(Self.colors(of:)) ?? []
        iconColorCache[pid] = found
        return found
    }

    /// An icon's own colors, biggest first: its real colors, or only for icons without any (ChatGPT,
    /// Cursor), its black and grays. White and off-white are left out, as they're the background of so
    /// many icons.
    private static func colors(of icon: NSImage) -> [NSColor] {
        let side = 32
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
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
                let key = saturation < 0.18 || brightness < 0.2
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
                .map { NSColor(srgbRed: $0.value.red / $0.value.count, green: $0.value.green / $0.value.count,
                               blue: $0.value.blue / $0.value.count, alpha: 1) }
        }
        return colored.isEmpty ? averages(grays) : averages(colored)
    }
}

/// How a plate in a given color is drawn, and whether text on it should be white.
private struct PlateStyle {
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

/// The glass plate behind neighboring windows of one app, tinted with the app's color. Drawn rather
/// than a real glass view: glass on glass hides the tint.
private final class PlateView: NSView {
    var tint: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let radius: CGFloat = 18
        let body = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        // Frosted base, so the color reads the same whatever is behind the panel, then the app's color.
        (isDark ? NSColor.black.withAlphaComponent(0.3) : .white.withAlphaComponent(0.5)).setFill()
        body.fill()
        tint.withAlphaComponent(PlateStyle(tint: tint, isDark: isDark).tintAlpha).setFill()
        body.fill()
        // Sheen: light falling on the top of the glass.
        NSGradient(colors: [.white.withAlphaComponent(isDark ? 0.1 : 0.3), .white.withAlphaComponent(0)])?
            .draw(in: body, angle: -90)
        // Rim: a bright edge at the top fading toward the bottom.
        let rim = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        rim.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1))
        rim.windingRule = .evenOdd
        NSGradient(colors: [.white.withAlphaComponent(isDark ? 0.35 : 0.9), .white.withAlphaComponent(isDark ? 0.05 : 0.25)])?
            .draw(in: rim, angle: -90)
    }
}

/// One window: its picture with the app's icon on the corner (or just the icon until a picture
/// arrives), and its title underneath.
private final class TileView: NSView {
    var index = 0
    private(set) var windowID: CGWindowID = 0
    var onHover: (@MainActor (Int) -> Void)?
    var onClick: (@MainActor (Int) -> Void)?
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        }
    }
    /// White titles on dark plates, dark ones elsewhere.
    var hasLightTitle = false {
        didSet { titleLabel.textColor = hasLightTitle ? .white : .black.withAlphaComponent(0.85) }
    }

    private let thumbnailView = NSImageView()
    private let iconView = NSImageView()
    private let badgeView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var thumbnail: CGImage?
    private var isMinimized = false
    private var thumbnailBox = NSRect.zero

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 8
        thumbnailView.layer?.masksToBounds = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        badgeView.shadow = shadow
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .black.withAlphaComponent(0.85)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(thumbnailView)
        addSubview(iconView)
        addSubview(badgeView)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ item: WindowItem, index: Int, thumbnail: CGImage?, icon: NSImage?) {
        self.index = index
        windowID = item.id
        isMinimized = item.isMinimized
        titleLabel.stringValue = item.title.isEmpty ? item.appName : item.title
        iconView.image = icon
        badgeView.image = icon
        setThumbnail(thumbnail)
    }

    func setThumbnail(_ image: CGImage?) {
        thumbnail = image
        thumbnailView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        thumbnailView.isHidden = image == nil
        badgeView.isHidden = image == nil
        iconView.isHidden = image != nil
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let padding = Metrics.tilePadding
        thumbnailBox = NSRect(x: padding, y: padding, width: bounds.width - padding * 2,
                              height: bounds.height - padding * 2 - Metrics.titleGap - Metrics.titleHeight)
        var picture = thumbnailBox
        if let thumbnail {
            let scale = min(thumbnailBox.width / CGFloat(thumbnail.width), thumbnailBox.height / CGFloat(thumbnail.height))
            let size = NSSize(width: (CGFloat(thumbnail.width) * scale).rounded(),
                              height: (CGFloat(thumbnail.height) * scale).rounded())
            picture = NSRect(x: thumbnailBox.midX - size.width / 2, y: thumbnailBox.midY - size.height / 2,
                             width: size.width, height: size.height)
            thumbnailView.frame = picture
        }
        let iconSide = min(96, thumbnailBox.height * 0.5)
        iconView.frame = NSRect(x: thumbnailBox.midX - iconSide / 2, y: thumbnailBox.midY - iconSide / 2,
                                width: iconSide, height: iconSide)
        // The app's icon hangs on the picture's bottom-left corner, sized with the picture.
        let badge = min(48, max(24, thumbnailBox.height * 0.2))
        badgeView.frame = NSRect(x: max(2, picture.minX - badge * 0.2), y: picture.maxY - badge * 0.85,
                                 width: badge, height: badge)
        titleLabel.frame = NSRect(x: padding, y: thumbnailBox.maxY + Metrics.titleGap,
                                  width: bounds.width - padding * 2, height: Metrics.titleHeight)
        // Minimized windows are shown faded, like in the Dock.
        thumbnailView.alphaValue = isMinimized ? 0.5 : 1
        iconView.alphaValue = isMinimized ? 0.5 : 1
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 14, yRadius: 14)
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            outline.fill()
            outline.lineWidth = 2.5
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }
        if thumbnail == nil {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: thumbnailBox, xRadius: 8, yRadius: 8).fill()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(index) }
    // Only real pointer movement selects, so tiles appearing under a resting pointer don't.
    override func mouseMoved(with event: NSEvent) { onHover?(index) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private extension NSScreen {
    static var underPointer: NSScreen {
        let pointer = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(pointer) } ?? main ?? screens[0]
    }
}
