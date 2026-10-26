import AppKit
import Testing

@testable import TabWindo

struct GridLayoutTests {
    private let screen = NSRect(x: 0, y: 0, width: 1728, height: 1080)

    /// One window per entry, owned by the given app.
    private func windows(_ pids: [pid_t]) -> [WindowItem] {
        pids.enumerated().map { index, pid in
            WindowItem(
                id: CGWindowID(index + 1), pid: pid, element: AXUIElementCreateApplication(pid),
                title: "Window \(index)", appName: "App \(pid)", isMinimized: false)
        }
    }

    @Test func wrapsAtTheChosenNumberPerRow() {
        let layout = GridLayout(windows(Array(repeating: 1, count: 10)), columns: 4, on: screen)
        #expect(layout.frames.count == 10)
        #expect(layout.frames[4].minX == 0)
        #expect(layout.frames[4].minY > layout.frames[3].minY)
        #expect(layout.frames[9].minX == layout.frames[1].minX)
    }

    @Test func fullRowSpansTheSameShareOfTheScreenWhateverTheCount() {
        let expected = screen.width * Metrics.widthShare - Metrics.inset * 2
        for columns in 2...7 {
            let layout = GridLayout(windows(Array(repeating: 1, count: columns)), columns: columns, on: screen)
            #expect(abs(layout.size.width - expected) < CGFloat(columns))  // each cell is rounded down
        }
    }

    @Test func fewerWindowsThanColumnsKeepsTheTileSize() {
        let full = GridLayout(windows([1, 2, 3, 4]), columns: 4, on: screen)
        let short = GridLayout(windows([1, 2]), columns: 4, on: screen)
        #expect(short.thumbnail == full.thumbnail)
        #expect(short.size.width < full.size.width)
    }

    @Test func neighborsFromTheSameAppShareAPlate() {
        // A A B on the first row, A A A on the second.
        let layout = GridLayout(windows([1, 1, 2, 1, 1, 1]), columns: 3, on: screen)
        #expect(layout.plates.map { $0.pid } == [1, 2, 1])
        #expect(layout.plates[0].frame == layout.frames[0].union(layout.frames[1]))
        #expect(layout.plates[2].frame == layout.frames[3].union(layout.frames[5]))
    }

    @Test func aRunOfOneAppSplitsAtTheEndOfARow() {
        let layout = GridLayout(windows([1, 1, 1, 1, 1]), columns: 3, on: screen)
        #expect(layout.plates.count == 2)
    }

    @Test func upAndDownKeepTheColumnAndWrapAround() {
        let layout = GridLayout(windows(Array(repeating: 1, count: 10)), columns: 4, on: screen)
        #expect(layout.neighbor(of: 1, lines: 1) == 5)
        #expect(layout.neighbor(of: 5, lines: -1) == 1)
        #expect(layout.neighbor(of: 1, lines: -1) == 9)
        #expect(layout.neighbor(of: 3, lines: 2) == 9)  // the last row is short: lands on its last tile
    }
}
