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
    var columns = Settings.columns
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
    private var lockObserver: NSObjectProtocol?

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
        // Nothing of ours stays up at the lock screen. Faking this only cancels a switch, so a notification will do.
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: .screenLocked, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(commit: false) }
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
        // The hot key still fires at the lock screen; nothing may be captured or shown there.
        guard !windows.isEmpty, !isScreenLocked() else { return }
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
        logger.debug(
            "Panel shown in \(Self.ms(since: start), format: .fixed(precision: 2), privacy: .public) ms, \(Self.ms(since: self.startedAt), format: .fixed(precision: 1), privacy: .public) ms after the key, \(session.count, privacy: .public) windows"
        )
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
        logger.debug(
            "Switched after \(Self.ms(since: self.startedAt), format: .fixed(precision: 1), privacy: .public) ms")
    }

    /// Lays the windows out for the screen under the pointer.
    private static func arrange(_ windows: [WindowItem], columns: Int) -> (layout: GridLayout, screen: NSScreen) {
        let screen = NSScreen.underPointer
        return (GridLayout(count: windows.count, columns: columns, on: screen.visibleFrame), screen)
    }

    private func schedule(
        after interval: TimeInterval, repeats: Bool,
        _ action: @escaping @MainActor (Switcher) -> Void
    ) -> Timer {
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

private extension NSScreen {
    static var underPointer: NSScreen {
        let pointer = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(pointer) } ?? main ?? screens[0]
    }
}
