import AppKit

/// The glass plate behind neighboring windows of one app, tinted with the app's color. Drawn rather
/// than a real glass view: glass on glass hides the tint.
final class PlateView: NSView {
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
final class TileView: NSView {
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

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
