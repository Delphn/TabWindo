import AppKit
import Testing

@testable import TabWindo

@MainActor
struct TileViewTests {
    @Test func theTitleFollowsTheMacBetweenLightAndDark() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered,
            defer: true)
        let tile = TileView()
        try #require(window.contentView).addSubview(tile)
        let yellow = NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        tile.tint = PlateColors.plateColor(light: yellow, dark: PlateColors.darkTone(yellow))
        #expect(!tile.hasLightTitle)
        window.appearance = NSAppearance(named: .darkAqua)
        #expect(tile.hasLightTitle)
        window.appearance = NSAppearance(named: .aqua)
        #expect(!tile.hasLightTitle)
    }
}
