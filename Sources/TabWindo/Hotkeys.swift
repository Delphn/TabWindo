import AppKit
import Carbon.HIToolbox

/// The key held down while tapping Tab.
enum Modifier: String, CaseIterable {
    case command, option, control

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        }
    }

    var carbonFlag: UInt32 {
        switch self {
        case .command: UInt32(cmdKey)
        case .option: UInt32(optionKey)
        case .control: UInt32(controlKey)
        }
    }
}

/// Turns modifier+Tab into switcher actions, plus Esc/Return/arrows while the switcher is open.
///
/// ⌘Tab and ⌃Tab are Carbon hot keys, which keep working inside password fields. macOS 15+ refuses
/// Option-only hot keys, so ⌥Tab is read from an event tap instead.
@MainActor
final class Hotkeys {
    enum Action { case next, previous, up, down, confirm, cancel }

    var onAction: (@MainActor (Action) -> Void)?
    /// While open, the tap drives the switcher and swallows every other key press.
    var isSwitcherOpen = false { didSet { updateTap() } }

    private var modifier = Modifier.command
    private var hotKeys: [EventHotKeyRef] = []
    private var tabUsesTap = false
    private var tap: CFMachPort?
    private var isHandlerInstalled = false

    func install(_ modifier: Modifier) {
        uninstall()
        self.modifier = modifier
        installHandler()
        installTap()
        if modifier == .command { setNativeCommandTab(enabled: false) }
        tabUsesTap =
            modifier == .option
            || !(register(modifier.carbonFlag, id: 1) && register(modifier.carbonFlag | UInt32(shiftKey), id: 2))
        if tabUsesTap { unregisterAll() }
        updateTap()
        logger.notice(
            "Shortcut \(modifier.symbol, privacy: .public)Tab via \(self.tabUsesTap ? "event tap" : "hot key", privacy: .public)"
        )
    }

    /// Releases the shortcut and gives ⌘Tab back to macOS.
    func uninstall() {
        unregisterAll()
        setNativeCommandTab(enabled: true)
    }

    private func register(_ modifiers: UInt32, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x5441_4257, id: id)  // "TABW"
        guard
            RegisterEventHotKey(UInt32(kVK_Tab), modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
                == OSStatus(noErr), let ref
        else { return false }
        hotKeys.append(ref)
        return true
    }

    private func unregisterAll() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
    }

    private func installHandler() {
        guard !isHandlerInstalled else { return }
        isHandlerInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotkeys.onAction?(hotKeyID.id == 2 ? .previous : .next) }
                return OSStatus(noErr)
            }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func installTap() {
        guard tap == nil else { return }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue),
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                let swallow = MainActor.assumeIsolated { hotkeys.handle(type, keyCode: keyCode, flags: flags) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            logger.error("Event tap unavailable; is Accessibility access granted?")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }

    /// Returns true to swallow the key press.
    private func handle(_ type: CGEventType, keyCode: Int, flags: CGEventFlags) -> Bool {
        switch type {
        case .keyDown:
            break
        case .tapDisabledByTimeout:
            updateTap()  // macOS switches a slow tap off; turn it back on if it should be running
            return false
        default:
            return false  // includes .tapDisabledByUserInput, which is just our own updateTap()
        }
        if keyCode == kVK_Tab, tabUsesTap, flags.contains(modifier.eventFlag), flags.isDisjoint(with: otherModifiers) {
            onAction?(flags.contains(.maskShift) ? .previous : .next)
            return true
        }
        guard isSwitcherOpen, keyCode != kVK_Tab else { return false }  // Tab belongs to the hot keys
        switch keyCode {
        case kVK_Escape: onAction?(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter: onAction?(.confirm)
        case kVK_LeftArrow: onAction?(.previous)
        case kVK_RightArrow: onAction?(.next)
        case kVK_UpArrow: onAction?(.up)
        case kVK_DownArrow: onAction?(.down)
        default: break  // swallowed, so ⌘Q, ⌘W… can't reach the app behind the switcher
        }
        return true
    }

    private var otherModifiers: CGEventFlags {
        CGEventFlags([.maskCommand, .maskAlternate, .maskControl]).subtracting(modifier.eventFlag)
    }

    private func updateTap() {
        guard let tap else { return }
        let shouldRun = tabUsesTap || isSwitcherOpen
        if CGEvent.tapIsEnabled(tap: tap) != shouldRun { CGEvent.tapEnable(tap: tap, enable: shouldRun) }
    }
}
