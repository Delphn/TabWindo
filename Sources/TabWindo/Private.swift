import AppKit

// Private macOS APIs, the same ones AltTab, yabai and Hammerspoon rely on. The two AX helpers are
// linked directly; the rest are looked up at runtime, so a missing one degrades instead of crashing.

@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

private func lookUp<T>(_ name: String, as type: T.Type) -> T? {
    // RTLD_DEFAULT: search the images already loaded (CoreGraphics, SkyLight, HIServices).
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }
}

private let getProcessForPID = lookUp(
    "GetProcessForPID", as: (@convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus).self)
private let setFrontProcess = lookUp(
    "_SLPSSetFrontProcessWithOptions",
    as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError).self)
private let postEventRecord = lookUp(
    "SLPSPostEventRecordTo",
    as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError).self)
private let setSymbolicHotKeyEnabled = lookUp(
    "CGSSetSymbolicHotKeyEnabled", as: (@convention(c) (Int32, Bool) -> CGError).self)
private let mainConnectionID = lookUp("CGSMainConnectionID", as: (@convention(c) () -> Int32).self)
private let copySpacesForWindows = lookUp(
    "CGSCopySpacesForWindows", as: (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?).self)

/// Turns the system's own ⌘Tab / ⌘⇧Tab app switcher (symbolic hot keys 1 and 2) on or off.
func setNativeCommandTab(enabled: Bool) {
    _ = setSymbolicHotKeyEnabled?(1, enabled)
    _ = setSymbolicHotKeyEnabled?(2, enabled)
}

/// False for windows on no Space at all, which is what the background tabs of a tabbed window are.
func isOnAnySpace(_ windowID: CGWindowID) -> Bool {
    guard let mainConnectionID, let copySpacesForWindows,
        let spaces = copySpacesForWindows(mainConnectionID(), 0x7, [windowID] as CFArray)?.takeRetainedValue()
    else { return true }
    return CFArrayGetCount(spaces) > 0
}

/// Brings one exact window to the front, switching Space if needed, as if it had been clicked.
func focusWindow(pid: pid_t, windowID: CGWindowID, element: AXUIElement) {
    var psn = ProcessSerialNumber()
    if let getProcessForPID, let setFrontProcess, getProcessForPID(pid, &psn) == OSStatus(noErr) {
        _ = setFrontProcess(&psn, windowID, 0x200)  // kCPSUserGenerated
        makeKeyWindow(&psn, windowID)
    } else {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
}

/// Makes the window key inside its app (port of yabai's window_manager_make_key_window).
private func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
    guard let postEventRecord else { return }
    for kind: UInt8 in [0x01, 0x02] {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x08] = kind
        bytes[0x3a] = 0x10
        bytes.replaceSubrange(0x20..<0x30, with: repeatElement(UInt8(0xff), count: 0x10))
        withUnsafeBytes(of: windowID) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        _ = postEventRecord(&psn, &bytes)
    }
}
