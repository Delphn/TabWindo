import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = WindowStore()
    private let hotkeys = Hotkeys()
    private let switcher = Switcher()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var isRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitIfAlreadyRunning()
        statusItem.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "TabWindo")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        CommandTabGuard.install()
        #if DEBUG
            if let seconds = DevTools.hangSeconds(in: CommandLine.arguments) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Thread.sleep(forTimeInterval: seconds) }
            }
        #endif
        if AXIsProcessTrusted() {
            run()
        } else {
            waitForAccessibility()
        }
    }

    /// A second copy would fight the first over ⌘Tab. The debug tools never get here, so `open -n … --list` still
    /// works beside the running app.
    private func quitIfAlreadyRunning() {
        let identifier = Bundle.main.bundleIdentifier ?? "dev.delphin.TabWindo"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != getpid() }
        guard !others.isEmpty else { return }
        logger.notice("Another TabWindo is already running; quitting")
        exit(0)  // not terminate(): that would hand ⌘Tab back while the other copy still wants it
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
        applyListing()
        use(Settings.modifier)
        // Previews need Screen Recording. macOS asks once and remembers the answer.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func use(_ modifier: Modifier) {
        Settings.modifier = modifier
        switcher.modifier = modifier.eventFlag
        if isRunning { hotkeys.install(modifier) }
    }

    /// Tells the store what to list, as chosen in the menu.
    private func applyListing() {
        guard isRunning else { return }
        store.show(otherSpaces: Settings.showsOtherSpaces, hiddenApps: Settings.showsHiddenApps)
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
            entry.state = option == Settings.modifier ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let perRow = NSMenuItem(title: "Windows per Row", action: nil, keyEquivalent: "")
        perRow.submenu = NSMenu()
        for count in 2...7 {
            let entry = item("\(count)", #selector(pickColumns(_:)))
            entry.tag = count
            entry.state = count == Settings.columns ? .on : .off
            perRow.submenu?.addItem(entry)
        }
        menu.addItem(perRow)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Show"))
        let otherSpaces = item("Other Desktops and Full Screen", #selector(toggleOtherSpaces))
        otherSpaces.state = Settings.showsOtherSpaces ? .on : .off
        menu.addItem(otherSpaces)
        let hiddenApps = item("Hidden Apps", #selector(toggleHiddenApps))
        hiddenApps.state = Settings.showsHiddenApps ? .on : .off
        menu.addItem(hiddenApps)
        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit TabWindo", action: #selector(NSApplication.terminate(_:)),
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
        Settings.columns = sender.tag
        switcher.columns = sender.tag
    }

    @objc private func toggleOtherSpaces() {
        Settings.showsOtherSpaces.toggle()
        applyListing()
    }

    @objc private func toggleHiddenApps() {
        Settings.showsHiddenApps.toggle()
        applyListing()
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
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
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
