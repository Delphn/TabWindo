import AppKit

/// A color in Oklch: lightness, chroma (how colorful it is) and hue, from Björn Ottosson's Oklab. Unlike HSB, equal
/// steps in it look equal, so plate colors are compared, and toned for dark mode, in it.
struct OKLCH {
    /// 0 is black, 1 is white.
    var lightness: CGFloat
    /// 0 is gray. The most vivid sRGB colors reach about 0.32.
    var chroma: CGFloat
    /// In radians.
    var hue: CGFloat

    init(lightness: CGFloat, chroma: CGFloat, hue: CGFloat) {
        (self.lightness, self.chroma, self.hue) = (lightness, chroma, hue)
    }

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        let (r, g, b) = (Self.linear(rgb.redComponent), Self.linear(rgb.greenComponent), Self.linear(rgb.blueComponent))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        self.init(
            lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, chroma: hypot(a, bAxis),
            hue: atan2(bAxis, a))
    }

    /// The sRGB color. One too vivid for sRGB loses chroma, never hue or lightness.
    var color: NSColor {
        let lightness = min(max(self.lightness, 0), 1)
        var fitting = chroma
        if Self.linearRGB(lightness, chroma, hue) == nil {
            var tooVivid = chroma
            fitting = 0
            for _ in 0..<20 {
                let middle = (fitting + tooVivid) / 2
                if Self.linearRGB(lightness, middle, hue) == nil { tooVivid = middle } else { fitting = middle }
            }
        }
        let channels = (Self.linearRGB(lightness, fitting, hue) ?? [0, 0, 0]).map { Self.encoded(min(max($0, 0), 1)) }
        return NSColor(srgbRed: channels[0], green: channels[1], blue: channels[2], alpha: 1)
    }

    /// How different two colors look: about 0.02 is just visible, 0.1 is plain.
    func distance(to other: OKLCH) -> CGFloat {
        let da = chroma * cos(hue) - other.chroma * cos(other.hue)
        let db = chroma * sin(hue) - other.chroma * sin(other.hue)
        return ((lightness - other.lightness) * (lightness - other.lightness) + da * da + db * db).squareRoot()
    }

    /// Linear sRGB for these coordinates, or nil when the color is outside sRGB.
    private static func linearRGB(_ lightness: CGFloat, _ chroma: CGFloat, _ hue: CGFloat) -> [CGFloat]? {
        let (a, b) = (chroma * cos(hue), chroma * sin(hue))
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let rgb = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        return rgb.allSatisfy { (-0.0001...1.0001).contains($0) } ? rgb : nil
    }

    private static func linear(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ channel: CGFloat) -> CGFloat {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}
