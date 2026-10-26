import Testing

@testable import TabWindo

struct WindowListingTests {
    private func lists(
        minimized: Bool = false, hidden: Bool = false, onScreen: Bool = false, onASpace: Bool = true,
        otherSpaces: Bool = true, hiddenApps: Bool = false
    ) -> Bool {
        WindowStore.lists(
            isMinimized: minimized, appIsHidden: hidden, isOnScreen: onScreen, isOnAnySpace: onASpace,
            otherSpaces: otherSpaces, hiddenApps: hiddenApps)
    }

    @Test func byDefaultOtherDesktopsAreListedAndHiddenAppsAreNot() {
        #expect(lists(onScreen: true))
        #expect(lists(onScreen: false))  // on another desktop or full screen
        #expect(lists(minimized: true, onASpace: false))
        #expect(!lists(hidden: true))
        #expect(!lists(onScreen: true, onASpace: false))  // a background window tab
    }

    @Test func withoutOtherDesktopsOnlyWhatIsOnScreenAndMinimizedWindows() {
        #expect(lists(onScreen: true, otherSpaces: false))
        #expect(!lists(onScreen: false, otherSpaces: false))
        #expect(lists(minimized: true, onASpace: false, otherSpaces: false))
    }

    @Test func hiddenAppsAreListedWhenAskedWhateverTheDesktopSetting() {
        #expect(lists(hidden: true, hiddenApps: true))
        #expect(lists(hidden: true, otherSpaces: false, hiddenApps: true))
        #expect(!lists(hidden: true, onASpace: false, hiddenApps: true))  // a hidden app's background tab
        #expect(lists(minimized: true, hidden: true, onASpace: false, hiddenApps: true))
    }
}
