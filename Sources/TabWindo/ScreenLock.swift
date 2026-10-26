import AppKit

/// Whether the Mac is at its lock screen, as macOS reports it. Any local process can fake a lock notification;
/// nothing can fake this, so it's what decides whether a switch may start.
func isScreenLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
}

extension Notification.Name {
    /// Posted by macOS when the screen locks and unlocks. Used only for things that do no harm if faked.
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
}
