import AppKit
import Testing

@testable import TabWindo

struct PlateColorsTests {
    private let blue = NSColor(srgbRed: 0.2, green: 0.5, blue: 1, alpha: 1)
    private let green = NSColor(srgbRed: 0.2, green: 0.8, blue: 0.3, alpha: 1)
    private let red = NSColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1)
    private let yellow = NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1)

    /// A 64×64 icon: an optional background, then rectangles given in unit coordinates.
    private func icon(background: NSColor? = nil, _ parts: [(NSRect, NSColor)] = []) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            if let background {
                background.setFill()
                rect.fill()
            }
            for (unit, color) in parts {
                color.setFill()
                NSRect(x: unit.minX * 64, y: unit.minY * 64, width: unit.width * 64, height: unit.height * 64).fill()
            }
            return true
        }
    }

    // MARK: Reading an icon's colors

    @Test func takesTheIconsMainColor() throws {
        let colors = PlateColors.colors(
            of: icon(background: .white, [(NSRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), green)]))
        let first = try #require(colors.first?.usingColorSpace(.sRGB))
        #expect(abs(first.greenComponent - 0.8) < 0.05)
    }

    @Test func blackLogoOnWhiteGivesBlack() throws {
        let colors = PlateColors.colors(
            of: icon(background: .white, [(NSRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), .black)]))
        let first = try #require(colors.first?.usingColorSpace(.sRGB))
        #expect(first.brightnessComponent < 0.2)
    }

    @Test func aWhiteIconGivesWhite() throws {
        let colors = PlateColors.colors(of: icon(background: .white))
        #expect(colors.count == 1)
        let first = try #require(colors.first?.usingColorSpace(.sRGB))
        #expect(first.brightnessComponent > 0.9)
    }

    @Test func aLogosColorIsNotDulledByItsShading() throws {
        // A bright red logo on a dark red background: the red is the logo's, not an average of the two.
        let darkRed = NSColor(srgbRed: 0.25, green: 0.05, blue: 0.05, alpha: 1)
        let brightRed = NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1)
        let colors = PlateColors.colors(
            of: icon(background: darkRed, [(NSRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), brightRed)]))
        let first = try #require(colors.first?.usingColorSpace(.sRGB))
        #expect(first.brightnessComponent > 0.9)
    }

    @Test func aColoredLogoWinsOverGrays() throws {
        let colors = PlateColors.colors(
            of: icon(background: .darkGray, [(NSRect(x: 0, y: 0, width: 0.5, height: 0.5), blue)]))
        let first = try #require(colors.first?.usingColorSpace(.sRGB))
        #expect(first.blueComponent > 0.8)
        #expect(colors.allSatisfy { ($0.usingColorSpace(.sRGB)?.saturationComponent ?? 0) > 0.18 })
    }

    @Test func theBiggestColorComesFirst() throws {
        let colors = PlateColors.colors(
            of: icon([
                (NSRect(x: 0, y: 0, width: 1, height: 0.7), yellow),
                (NSRect(x: 0, y: 0.7, width: 1, height: 0.3), red),
            ]))
        #expect(colors.count == 2)
        let first = try #require(colors.first?.usingColorSpace(.sRGB))
        #expect(first.greenComponent > 0.6)  // the yellow
    }

    // MARK: Telling colors apart

    @Test func sameHueAtAnotherLightnessIsNotAlike() {
        let navy = NSColor(hue: blue.hueComponent, saturation: blue.saturationComponent, brightness: 0.4, alpha: 1)
        #expect(PlateColors.areAlike(blue, blue))
        #expect(!PlateColors.areAlike(blue, navy))
    }

    // MARK: Choosing a color per app

    @Test func aSecondAppWithTheSameColorGetsAShadeOfIt() throws {
        let chosen = PlateColors.assign([(pid: 1, colors: [blue]), (pid: 2, colors: [blue])], keeping: [:])
        let first = try #require(chosen[1])
        let second = try #require(chosen[2])
        #expect(first == blue)
        #expect(!PlateColors.areAlike(first, second))
    }

    @Test func aMulticolorAppMovesToItsNextColor() {
        // The single-color app chooses first and keeps green; the other falls back to its red.
        let chosen = PlateColors.assign([(pid: 1, colors: [green, red]), (pid: 2, colors: [green])], keeping: [:])
        #expect(chosen[2] == green)
        #expect(chosen[1] == red)
    }

    @Test func anAppKeepsItsColorWhileItIsStillFree() {
        let orange = NSColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1)
        let chosen = PlateColors.assign([(pid: 1, colors: [blue, orange])], keeping: [1: orange])
        #expect(chosen[1] == orange)
    }

    // MARK: Dark mode

    @Test func darkModeKeepsTheHueButCalmsTheColor() {
        for color in [blue, green, red, yellow] {
            let tone = OKLCH(PlateColors.darkTone(color))
            #expect((0.3...0.5).contains(tone.lightness))
            #expect(tone.chroma <= 0.101)
            #expect(abs(remainder(tone.hue - OKLCH(color).hue, 2 * .pi)) < 0.05)
        }
    }

    @Test func blackStaysVisibleOnTheDarkPanel() {
        #expect(OKLCH(PlateColors.darkTone(.black)).lightness > 0.29)
    }

    @Test func inDarkModeASecondAppWithTheSameColorGetsAShadeOfIt() throws {
        let chosen = PlateColors.assign(
            [(pid: 1, colors: [blue]), (pid: 2, colors: [blue])], keeping: [:], isDark: true)
        let first = try #require(chosen[1])
        let second = try #require(chosen[2])
        #expect(PlateColors.areAlike(first, PlateColors.darkTone(blue)))
        #expect(!PlateColors.areAlike(first, second))
    }

    @Test func aPlateColorFollowsTheAppearance() throws {
        let color = PlateColors.plateColor(light: yellow, dark: blue)
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        #expect(PlateColors.areAlike(color.resolved(in: light), yellow))
        #expect(PlateColors.areAlike(color.resolved(in: dark), blue))
    }

    @Test func darkPlatesGetWhiteTitles() {
        for color in [blue, green, red, yellow, .white, .black] {
            #expect(PlateStyle(tint: PlateColors.darkTone(color), isDark: true).wantsLightText)
        }
    }
}
