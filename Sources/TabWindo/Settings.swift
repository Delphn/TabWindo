import AppKit

/// What the user chose in the menu bar menu, kept by macOS in UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// The key held down while tapping Tab.
    static var modifier: Modifier {
        get { Modifier(rawValue: defaults.string(forKey: "modifier") ?? "") ?? .command }
        set { defaults.set(newValue.rawValue, forKey: "modifier") }
    }

    /// Windows per row in the switcher: 2 to 7, 4 by default.
    static var columns: Int {
        get {
            let saved = defaults.integer(forKey: "columns")
            return (2...7).contains(saved) ? saved : 4
        }
        set { defaults.set(newValue, forKey: "columns") }
    }

    /// Whether windows on other desktops, full-screen apps included, are listed. On unless turned off.
    static var showsOtherSpaces: Bool {
        get { defaults.object(forKey: "otherSpaces") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "otherSpaces") }
    }

    /// Whether the windows of hidden (⌘H) apps are listed. Off unless turned on.
    static var showsHiddenApps: Bool {
        get { defaults.bool(forKey: "hiddenApps") }
        set { defaults.set(newValue, forKey: "hiddenApps") }
    }
}
