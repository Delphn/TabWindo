import AppKit
import Testing

@testable import TabWindo

struct WindowOrderTests {
    @Test func mostRecentFirstMinimizedLastNewerFirstOnATie() {
        let windows: [(id: CGWindowID, lastUse: UInt64, isMinimized: Bool)] = [
            (1, 5, false), (2, 9, true), (3, 7, false), (4, 7, false), (5, 1, true),
        ]
        let order = windows.sorted { WindowStore.comesBefore($0, $1) }.map { $0.id }
        #expect(order == [4, 3, 1, 2, 5])
    }
}
