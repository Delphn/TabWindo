import AppKit

/// Sizes and spacing of the switcher panel, in points.
enum Metrics {
    /// A full row spans this share of the screen's width, so fewer windows per row means bigger
    /// previews rather than a narrower panel.
    static let widthShare: CGFloat = 0.7
    /// Past this share of the screen's height, the panel scrolls.
    static let heightShare: CGFloat = 0.9
    static let inset: CGFloat = 16
    static let thumbnailAspect: CGFloat = 16 / 10
    static let tilePadding: CGFloat = 8
    static let titleGap: CGFloat = 6
    static let titleHeight: CGFloat = 16
    static let columnGap: CGFloat = 10
    static let lineGap: CGFloat = 10
}

/// Where each window goes: a fixed number per row, most recent first, simply wrapping. Every window
/// sits on a plate in its app's color, shared with neighbors from the same app.
struct GridLayout {
    let thumbnail: NSSize
    let frames: [NSRect]
    let plates: [(frame: NSRect, pid: pid_t)]
    let size: NSSize
    /// The tallest the grid gets before the panel scrolls.
    let maxHeight: CGFloat
    private let columns: Int
    private let lineCount: Int

    init(_ windows: [WindowItem], columns: Int, on area: NSRect) {
        let count = windows.count
        let lines = max(1, (count + columns - 1) / columns)
        let gridWidth = area.width * Metrics.widthShare - Metrics.inset * 2
        let cellWidth = ((gridWidth - CGFloat(columns - 1) * Metrics.columnGap) / CGFloat(columns)).rounded(.down)
        thumbnail = NSSize(width: cellWidth - Metrics.tilePadding * 2,
                           height: ((cellWidth - Metrics.tilePadding * 2) / Metrics.thumbnailAspect).rounded())
        let cell = NSSize(width: cellWidth,
                          height: thumbnail.height + Metrics.tilePadding * 2 + Metrics.titleGap + Metrics.titleHeight)
        maxHeight = area.height * Metrics.heightShare - Metrics.inset * 2
        frames = (0..<count).map { index in
            NSRect(x: CGFloat(index % columns) * (cell.width + Metrics.columnGap),
                   y: CGFloat(index / columns) * (cell.height + Metrics.lineGap), width: cell.width, height: cell.height)
        }
        // One plate per run of neighboring windows from the same app on a line.
        var plates: [(frame: NSRect, pid: pid_t)] = []
        var runStart = 0
        for index in windows.indices {
            let isRunEnd = index == count - 1 || windows[index + 1].pid != windows[index].pid
                || (index + 1) % columns == 0
            guard isRunEnd else { continue }
            plates.append((frames[runStart].union(frames[index]), windows[index].pid))
            runStart = index + 1
        }
        self.plates = plates
        self.columns = columns
        lineCount = lines
        let used = CGFloat(min(columns, max(count, 1)))
        size = NSSize(width: used * (cell.width + Metrics.columnGap) - Metrics.columnGap,
                      height: CGFloat(lines) * (cell.height + Metrics.lineGap) - Metrics.lineGap)
    }

    /// The tile in the same column on the line above or below, wrapping around.
    func neighbor(of index: Int, lines step: Int) -> Int {
        guard frames.indices.contains(index), lineCount > 1 else { return index }
        let line = (index / columns + step + lineCount) % lineCount
        return min(line * columns + index % columns, frames.count - 1)
    }
}
