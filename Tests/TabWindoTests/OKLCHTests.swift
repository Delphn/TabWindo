import AppKit
import Testing

@testable import TabWindo

struct OKLCHTests {
    @Test func matchesTheReferenceValuesForRed() {
        // From Björn Ottosson's Oklab post: sRGB red is (0.628, 0.225, 0.126).
        let red = OKLCH(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        #expect(abs(red.lightness - 0.628) < 0.001)
        #expect(abs(red.chroma * cos(red.hue) - 0.225) < 0.001)
        #expect(abs(red.chroma * sin(red.hue) - 0.126) < 0.001)
    }

    @Test func goesBackToTheSameColor() throws {
        let colors: [NSColor] = [
            .white, .black, NSColor(srgbRed: 0.2, green: 0.5, blue: 1, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.8, blue: 0.1, alpha: 1),
        ]
        for color in colors {
            let original = try #require(color.usingColorSpace(.sRGB))
            let back = try #require(OKLCH(color).color.usingColorSpace(.sRGB))
            #expect(abs(back.redComponent - original.redComponent) < 0.002)
            #expect(abs(back.greenComponent - original.greenComponent) < 0.002)
            #expect(abs(back.blueComponent - original.blueComponent) < 0.002)
        }
    }

    @Test func aColorTooVividForSRGBLosesChromaNotHue() {
        let fitted = OKLCH(OKLCH(lightness: 0.5, chroma: 0.5, hue: 2).color)
        #expect(fitted.chroma < 0.5)
        #expect(abs(fitted.lightness - 0.5) < 0.01)
        #expect(abs(fitted.hue - 2) < 0.02)
    }
}
