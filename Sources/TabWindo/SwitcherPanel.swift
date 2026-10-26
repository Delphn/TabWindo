import AppKit

/// The Liquid Glass panel. Built once, reused for every switch, and never takes focus from the app
/// behind it.
@MainActor
final class SwitcherPanel {
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
    private lazy var colors = PlateColors { [unowned self] pid in self.icon(for: pid) }

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
        colors.assign(to: Set(items.map(\.pid)))
        let isDark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for (index, plate) in layout.plates.enumerated() {
            let view = plateView(at: index)
            view.frame = plate.frame
            view.tint = colors.color(for: plate.pid)
        }
        plates.dropFirst(layout.plates.count).forEach { $0.isHidden = true }
        for (index, item) in items.enumerated() {
            let tile = tileView(at: index)
            tile.frame = layout.frames[index]
            tile.show(item, index: index, thumbnail: thumbnails[item.id], icon: icon(for: item.pid))
            tile.hasLightTitle = PlateStyle(tint: colors.color(for: item.pid), isDark: isDark).wantsLightText
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
}
