import AppKit
import os

/// App-wide log. Only counts and timings go in here, never window titles.
let logger = Logger(subsystem: "dev.delphin.TabWindo", category: "switcher")

/// One window as the switcher shows it.
struct WindowItem {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    let title: String
    let appName: String
    let isMinimized: Bool
}

/// Keeps every window in most-recently-used order, updated from Accessibility notifications on its
/// own thread, so pressing the shortcut never has to ask an app anything.
final class WindowStore: NSObject {
    /// Gets the latest list on the main thread: most recent first, minimized windows last.
    var onChange: (@MainActor ([WindowItem]) -> Void)?
    /// Called on the main thread once windows on other Spaces have been found.
    var onReady: (@MainActor () -> Void)?

    private final class TrackedApp {
        let pid: pid_t
        let element: AXUIElement
        let observer: AXObserver
        let name: String
        var isHidden: Bool

        init(pid: pid_t, element: AXUIElement, observer: AXObserver, name: String, isHidden: Bool) {
            self.pid = pid
            self.element = element
            self.observer = observer
            self.name = name
            self.isHidden = isHidden
        }
    }

    private final class TrackedWindow {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        var title: String
        var isMinimized: Bool
        var lastUse: UInt64 = 0

        init(id: CGWindowID, pid: pid_t, element: AXUIElement, title: String, isMinimized: Bool) {
            self.id = id
            self.pid = pid
            self.element = element
            self.title = title
            self.isMinimized = isMinimized
        }
    }

    // Only touched on the store's own thread.
    private var apps: [pid_t: TrackedApp] = [:]
    private var windows: [CGWindowID: TrackedWindow] = [:]
    private var clock: UInt64 = 0
    private var frontPID: pid_t = 0
    private var isPublishScheduled = false
    /// Set when the store started at the lock screen, where apps report no windows.
    private var needsFullRescan = false
    /// What's listed beyond the current desktop's windows; see `show(otherSpaces:hiddenApps:)`.
    private var showsOtherSpaces = true
    private var showsHiddenApps = false

    private var runLoop: CFRunLoop!
    private let focusQueue = DispatchQueue(label: "TabWindo.focus", qos: .userInteractive)

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            self.runLoop = CFRunLoopGetCurrent()
            RunLoop.current.add(NSMachPort(), forMode: .default)  // keeps the run loop alive
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "WindowStore"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(appLaunched), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appHidden), name: NSWorkspace.didHideApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appUnhidden), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked), name: .screenUnlocked, object: nil)

        let running = NSWorkspace.shared.runningApplications
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        perform { self.bootstrap(running, front: front) }
    }

    /// Brings the window forward off the main thread, so a frozen app can't stall the switcher.
    func focus(_ item: WindowItem) {
        perform {
            self.bump(item.id)
            self.setNeedsPublish()
        }
        focusQueue.async {
            if item.isMinimized {
                AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            focusWindow(pid: item.pid, windowID: item.id, element: item.element)
            self.perform {
                self.bump(item.id)
                self.setNeedsPublish()
            }
        }
    }

    /// Whether to list windows on other desktops (full-screen apps included) and the windows of hidden apps.
    /// Call after `start()`.
    func show(otherSpaces: Bool, hiddenApps: Bool) {
        perform {
            self.showsOtherSpaces = otherSpaces
            self.showsHiddenApps = hiddenApps
            self.setNeedsPublish()
        }
    }

    // MARK: - Store thread

    private func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func bootstrap(_ running: [NSRunningApplication], front: pid_t) {
        let start = CACurrentMediaTime()
        frontPID = front
        needsFullRescan = isScreenLocked()
        running.forEach { trackApp($0, attempt: 0) }
        seedOrderFromScreen()
        if let app = apps[front] { bumpFocusedWindow(of: app) }
        publish()
        logger.notice(
            "Tracking \(self.windows.count, privacy: .public) windows in \(self.apps.count, privacy: .public) apps after \(Self.ms(since: start), privacy: .public) ms"
        )
        discoverOtherSpaces(of: Array(apps.keys), thenNotify: true)
    }

    private func trackApp(_ app: NSRunningApplication, attempt: Int) {
        let pid = app.processIdentifier
        guard apps[pid] == nil, pid != getpid(), app.activationPolicy == .regular, !app.isTerminated else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else {
            return retry(app, attempt: attempt)
        }
        let added = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        guard added == .success || added == .notificationAlreadyRegistered else {
            return retry(app, attempt: attempt)  // usually an app that is still launching
        }
        AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        let tracked = TrackedApp(
            pid: pid, element: element, observer: observer,
            name: app.localizedName ?? "", isHidden: app.isHidden)
        apps[pid] = tracked
        tracked.element.windows.forEach { track($0, of: tracked) }
    }

    private func retry(_ app: NSRunningApplication, attempt: Int) {
        guard attempt < 6 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2 * Double(1 << attempt)) {
            self.perform { self.trackApp(app, attempt: attempt + 1) }
        }
    }

    private func track(_ element: AXUIElement, of app: TrackedApp) {
        guard let id = element.windowID, windows[id] == nil, element.isWindow else { return }
        windows[id] = TrackedWindow(
            id: id, pid: app.pid, element: element,
            title: element.attribute(kAXTitleAttribute) ?? "",
            isMinimized: element.attribute(kAXMinimizedAttribute) ?? false)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [
            kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        ] {
            AXObserverAddNotification(app.observer, element, name as CFString, refcon)
        }
    }

    fileprivate func handle(_ notification: String, _ element: AXUIElement) {
        let pid = element.pid
        switch notification {
        case kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification:
            guard let app = apps[pid] else { return }
            track(element, of: app)
            if pid == frontPID, let id = element.windowID { bump(id) }
        case kAXUIElementDestroyedNotification:
            guard let window = windows.values.first(where: { CFEqual($0.element, element) }) else { return }
            windows[window.id] = nil
        case kAXTitleChangedNotification:
            guard let id = element.windowID, let window = windows[id] else { return }
            window.title = element.attribute(kAXTitleAttribute) ?? window.title
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            guard let id = element.windowID, let window = windows[id] else { return }
            window.isMinimized = notification == kAXWindowMiniaturizedNotification
        default:
            return
        }
        setNeedsPublish()
    }

    private func bump(_ id: CGWindowID) {
        guard let window = windows[id] else { return }
        clock += 1
        window.lastUse = clock
    }

    private func bumpFocusedWindow(of app: TrackedApp) {
        guard let window = app.element.focusedWindow else { return }
        track(window, of: app)
        if let id = window.windowID { bump(id) }
    }

    /// At launch, the front-to-back order on screen is the best guess of recency.
    private func seedOrderFromScreen() {
        let onScreen = windowList([.optionOnScreenOnly, .excludeDesktopElements]).filter { windows[$0] != nil }
        for (rank, id) in onScreen.reversed().enumerated() { windows[id]?.lastUse = UInt64(rank + 1) }
        clock = UInt64(onScreen.count)
    }

    /// Drops windows the window server no longer has (some apps never send "destroyed").
    private func prune() {
        let alive = Set(windowList(.optionAll))
        windows = windows.filter { alive.contains($0.key) }
    }

    private func windowList(_ options: CGWindowListOption) -> [CGWindowID] {
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }

    private func setNeedsPublish() {
        guard !isPublishScheduled else { return }
        isPublishScheduled = true
        perform {
            self.isPublishScheduled = false
            self.publish()
        }
    }

    private func publish() {
        // Windows ordered in on any display's current desktop. Not needed while other desktops are listed too.
        let onScreen = showsOtherSpaces ? [] : Set(windowList(.optionOnScreenOnly))
        let items = windows.values
            .filter { window in
                guard let app = apps[window.pid] else { return false }
                return Self.lists(
                    isMinimized: window.isMinimized, appIsHidden: app.isHidden,
                    isOnScreen: onScreen.contains(window.id), isOnAnySpace: isOnAnySpace(window.id),
                    otherSpaces: showsOtherSpaces, hiddenApps: showsHiddenApps)
            }
            .sorted { Self.comesBefore(($0.id, $0.lastUse, $0.isMinimized), ($1.id, $1.lastUse, $1.isMinimized)) }
            .map {
                WindowItem(
                    id: $0.id, pid: $0.pid, element: $0.element, title: $0.title,
                    appName: apps[$0.pid]?.name ?? "", isMinimized: $0.isMinimized)
            }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onChange?(items) } }
    }

    /// Whether a window is listed. Minimized windows always are. A hidden app's windows only when asked. The rest
    /// must be on a desktop (background window tabs are on none) and, unless other desktops are listed, on screen.
    static func lists(
        isMinimized: Bool, appIsHidden: Bool, isOnScreen: Bool, isOnAnySpace: @autoclosure () -> Bool,
        otherSpaces: Bool, hiddenApps: Bool
    ) -> Bool {
        if appIsHidden, !hiddenApps { return false }
        if isMinimized { return true }
        if appIsHidden { return isOnAnySpace() }
        return otherSpaces ? isOnAnySpace() : isOnScreen
    }

    /// The switcher's order: most recently used first, minimized windows last, newer windows first on a tie.
    static func comesBefore(
        _ a: (id: CGWindowID, lastUse: UInt64, isMinimized: Bool),
        _ b: (id: CGWindowID, lastUse: UInt64, isMinimized: Bool)
    ) -> Bool {
        if a.isMinimized != b.isMinimized { return b.isMinimized }
        if a.lastUse != b.lastUse { return a.lastUse > b.lastUse }
        return a.id > b.id
    }

    // MARK: - Other Spaces

    /// The Accessibility API only lists windows on the current Space, so probe each app's element IDs
    /// directly (the technique AltTab uses) to find its windows on other Spaces and full-screen.
    private func discoverOtherSpaces(of pids: [pid_t], thenNotify notify: Bool) {
        DispatchQueue.global(qos: .utility).async {
            let start = CACurrentMediaTime()
            for pid in pids {
                let found = Self.probeWindows(of: pid)
                guard !found.isEmpty else { continue }
                self.perform {
                    guard let app = self.apps[pid] else { return }
                    found.forEach { self.track($0, of: app) }
                }
            }
            self.perform {
                self.publish()
                logger.notice(
                    "Scanned other Spaces in \(Self.ms(since: start), privacy: .public) ms, \(self.windows.count, privacy: .public) windows tracked"
                )
                if notify { DispatchQueue.main.async { MainActor.assumeIsolated { self.onReady?() } } }
            }
        }
    }

    private static func probeWindows(of pid: pid_t) -> [AXUIElement] {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: UInt32(0x636f_636f)) { Data($0) })  // "coco"
        var found: [AXUIElement] = []
        for elementID in UInt64(0)..<1000 {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else {
                continue
            }
            let start = CACurrentMediaTime()
            var subrole: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            if result == .cannotComplete, CACurrentMediaTime() - start > 0.1 { break }  // app isn't responding
            if let subrole = subrole as? String, subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole {
                found.append(element)
            }
        }
        return found
    }

    private static func ms(since start: CFTimeInterval) -> Int {
        Int((CACurrentMediaTime() - start) * 1000)
    }

    // MARK: - Workspace events (main thread, forwarded to the store thread)

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.runningApp else { return }
        perform { self.trackApp(app, attempt: 0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            self.discoverOtherSpaces(of: [app.processIdentifier], thenNotify: false)
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let pid = note.runningApp?.processIdentifier else { return }
        perform {
            guard let app = self.apps.removeValue(forKey: pid) else { return }
            CFRunLoopRemoveSource(self.runLoop, AXObserverGetRunLoopSource(app.observer), .defaultMode)
            self.windows = self.windows.filter { $0.value.pid != pid }
            self.setNeedsPublish()
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.runningApp else { return }
        perform {
            self.frontPID = app.processIdentifier
            if self.apps[app.processIdentifier] == nil { self.trackApp(app, attempt: 0) }
            if let tracked = self.apps[app.processIdentifier] { self.bumpFocusedWindow(of: tracked) }
            self.prune()
            self.setNeedsPublish()
        }
    }

    @objc private func appHidden(_ note: Notification) { setHidden(true, note) }
    @objc private func appUnhidden(_ note: Notification) { setHidden(false, note) }

    private func setHidden(_ isHidden: Bool, _ note: Notification) {
        guard let pid = note.runningApp?.processIdentifier else { return }
        perform {
            self.apps[pid]?.isHidden = isHidden
            self.setNeedsPublish()
        }
    }

    @objc private func spaceChanged(_ note: Notification) {
        perform { self.rescanCurrentSpace() }
    }

    /// Faking this notification only costs a rescan, so it needs no check against macOS.
    @objc private func screenUnlocked(_ note: Notification) {
        perform {
            self.rescanCurrentSpace()
            logger.notice("Unlocked; \(self.windows.count, privacy: .public) windows after a rescan")
            guard self.needsFullRescan else { return }
            self.needsFullRescan = false
            self.seedOrderFromScreen()
            self.discoverOtherSpaces(of: Array(self.apps.keys), thenNotify: false)
        }
    }

    private func rescanCurrentSpace() {
        for app in apps.values { app.element.windows.forEach { track($0, of: app) } }
        prune()
        setNeedsPublish()
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<WindowStore>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element)
}

private extension Notification {
    var runningApp: NSRunningApplication? {
        userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}

private extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var windows: [AXUIElement] { attribute(kAXWindowsAttribute) ?? [] }

    var focusedWindow: AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXFocusedWindowAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }

    /// Real windows only: no palettes, popovers, tooltips or sheets.
    var isWindow: Bool {
        guard let subrole: String = attribute(kAXSubroleAttribute) else { return false }
        return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }
}
