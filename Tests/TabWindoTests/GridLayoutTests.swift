import AppKit
import Testing

@testable import TabWindo

struct GridLayoutTests {
    private let screen = NSRect(x: 0, y: 0, width: 1728, height: 1080)

    @Test func wrapsAtTheChosenNumberPerRow() {
        let layout = GridLayout(count: 10, columns: 4, on: screen)
        #expect(layout.frames.count == 10)
        #expect(layout.frames[4].minX == 0)
        #expect(layout.frames[4].minY > layout.frames[3].minY)
        #expect(layout.frames[9].minX == layout.frames[1].minX)
    }

    @Test func fullRowSpansTheSameShareOfTheScreenWhateverTheCount() {
        let expected = screen.width * Metrics.widthShare - Metrics.inset * 2
        for columns in 2...7 {
            let layout = GridLayout(count: columns, columns: columns, on: screen)
            #expect(abs(layout.size.width - expected) < CGFloat(columns))  // each cell is rounded down
        }
    }

    @Test func fewerWindowsThanColumnsKeepsTheTileSize() {
        let full = GridLayout(count: 4, columns: 4, on: screen)
        let short = GridLayout(count: 2, columns: 4, on: screen)
        #expect(short.thumbnail == full.thumbnail)
        #expect(short.size.width < full.size.width)
    }

    @Test func everyWindowHasItsOwnTileWithAGapAround() {
        let layout = GridLayout(count: 10, columns: 4, on: screen)
        for (index, frame) in layout.frames.enumerated() {
            for other in layout.frames.dropFirst(index + 1) {
                #expect(!frame.insetBy(dx: -Metrics.columnGap / 2, dy: -Metrics.lineGap / 2).intersects(other))
            }
        }
    }

    @Test func upAndDownKeepTheColumnAndWrapAround() {
        let layout = GridLayout(count: 10, columns: 4, on: screen)
        #expect(layout.neighbor(of: 1, lines: 1) == 5)
        #expect(layout.neighbor(of: 5, lines: -1) == 1)
        #expect(layout.neighbor(of: 1, lines: -1) == 9)
        #expect(layout.neighbor(of: 3, lines: 2) == 9)  // the last row is short: lands on its last tile
    }
}
