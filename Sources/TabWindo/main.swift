import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = WindowStore()
    private let hotkeys = Hotkeys()
    private let switcher = Switcher()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var signalSources: [DispatchSourceSignal] = []
    private var isRunning = false

    private var modifier: Modifier {
        get { Modifier(rawValue: UserDefaults.standard.string(forKey: "modifier") ?? "") ?? .command }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "modifier") }
    }

    /// Windows per row in the switcher: 2 to 7, 4 by default.
    static var savedColumns: Int {
        let saved = UserDefaults.standard.integer(forKey: "columns")
        return (2...7).contains(saved) ? saved : 4
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                           accessibilityDescription: "TabWindo")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        restoreCommandTabOnSignals()
        if AXIsProcessTrusted() {
            run()
        } else {
            waitForAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.uninstall()
    }

    private func run() {
        guard !isRunning else { return }
        isRunning = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        store.onChange = { [switcher] windows in switcher.windows = windows }
        switcher.onFocus = { [store] window in store.focus(window) }
        switcher.onOpenChange = { [hotkeys] isOpen in hotkeys.isSwitcherOpen = isOpen }
        hotkeys.onAction = { [switcher] action in switcher.handle(action) }
        store.start()
        use(modifier)
        // Previews need Screen Recording. macOS asks once and remembers the answer.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func use(_ modifier: Modifier) {
        self.modifier = modifier
        switcher.modifier = modifier.eventFlag
        if isRunning { hotkeys.install(modifier) }
    }

    /// Shows the system's Accessibility prompt, then starts as soon as access is granted.
    private func waitForAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.run()
            }
        }
    }

    /// If the app is killed, hand ⌘Tab back to macOS before exiting.
    private func restoreCommandTabOnSignals() {
        for code in [SIGTERM, SIGINT, SIGHUP] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.hotkeys.uninstall() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Menu bar

    /// Filled in each time it opens, so permission and login states are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            menu.addItem(item("Allow Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        if !CGPreflightScreenCaptureAccess() {
            menu.addItem(item("Allow Screen Recording for Previews…", #selector(openScreenRecordingSettings)))
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(.sectionHeader(title: "Shortcut"))
        for option in Modifier.allCases {
            let entry = item("\(option.symbol) Tab", #selector(pickModifier(_:)))
            entry.representedObject = option.rawValue
            entry.state = option == modifier ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let perRow = NSMenuItem(title: "Windows per Row", action: nil, keyEquivalent: "")
        perRow.submenu = NSMenu()
        for count in 2...7 {
            let entry = item("\(count)", #selector(pickColumns(_:)))
            entry.tag = count
            entry.state = count == Self.savedColumns ? .on : .off
            perRow.submenu?.addItem(entry)
        }
        menu.addItem(perRow)
        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TabWindo", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pickModifier(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let picked = Modifier(rawValue: raw) else { return }
        use(picked)
    }

    @objc private func pickColumns(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "columns")
        switcher.columns = sender.tag
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Launch at Login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

MainActor.assumeIsolated {
    #if DEBUG
    let delegate: NSApplicationDelegate = DevTools.delegate(for: CommandLine.arguments) ?? AppDelegate()
    #else
    let delegate = AppDelegate()
    #endif
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
