/// ANSI 16-color palette indices.
public enum ANSIColor: Int, Sendable, Hashable {
    case black = 0, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
}

/// A terminal color that supports ANSI 16-color, xterm 256-color, and 24-bit RGB truecolor.
public enum Color: Sendable, Hashable {
    /// One of the 16 standard ANSI colors.
    case ansi(ANSIColor)
    /// An xterm 256-color palette index (0–255).
    case xterm(Int)
    /// 24-bit RGB truecolor.
    case rgb(UInt8, UInt8, UInt8)

    // MARK: - SGR sequences

    /// Foreground SGR escape sequence, e.g. `"\u{1B}[31m"`.
    public var foregroundSGR: String {
        SGR.encode(sgrParameters(isForeground: true))
    }

    /// Background SGR escape sequence, e.g. `"\u{1B}[41m"`.
    public var backgroundSGR: String {
        SGR.encode(sgrParameters(isForeground: false))
    }

    // MARK: - Reset sequences

    /// Resets all SGR attributes.
    public static var reset: String { "\u{1B}[0m" }
    /// Resets the foreground color to the terminal default.
    public static var resetForeground: String { "\u{1B}[39m" }
    /// Resets the background color to the terminal default.
    public static var resetBackground: String { "\u{1B}[49m" }

    // MARK: - Constructors

    /// Creates a `.rgb` color from a hex string.
    ///
    /// Accepts `"#RRGGBB"` or `"RRGGBB"` (case-insensitive).  Invalid input
    /// returns `.rgb(0, 0, 0)` for backwards compatibility; new code should
    /// prefer ``hexOrNil(_:)`` to detect malformed configuration explicitly.
    public static func hex(_ s: String) -> Color {
        hexOrNil(s) ?? .rgb(0, 0, 0)
    }

    /// Failable hex parser — returns `nil` for malformed input instead of
    /// silently producing black, so callers can surface configuration errors.
    ///
    /// Accepts `"#RRGGBB"` or `"RRGGBB"` (case-insensitive).
    public static func hexOrNil(_ s: String) -> Color? {
        var cleaned = s.hasPrefix("#") ? String(s.dropFirst()) : s
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return nil
        }
        return hex(value)
    }

    /// Creates a `.rgb` color from a packed 24-bit integer, e.g. `0xFF8000`.
    public static func hex(_ rgb: UInt32) -> Color {
        let r = UInt8((rgb >> 16) & 0xFF)
        let g = UInt8((rgb >> 8) & 0xFF)
        let b = UInt8(rgb & 0xFF)
        return .rgb(r, g, b)
    }

    // MARK: - Color operations

    /// Returns a lighter version of the color by shifting lightness toward 1.
    ///
    /// - Parameter amount: Value in 0...1 indicating how much to lighten.
    public func lighter(by amount: Double) -> Color {
        var (h, s, l) = toHSL()
        l = min(1.0, l + (1.0 - l) * amount)
        let (r, g, b) = hslToRGB(h: h, s: s, l: l)
        return .rgb(r, g, b)
    }

    /// Returns a darker version of the color by shifting lightness toward 0.
    ///
    /// - Parameter amount: Value in 0...1 indicating how much to darken.
    public func darker(by amount: Double) -> Color {
        var (h, s, l) = toHSL()
        l = max(0.0, l - l * amount)
        let (r, g, b) = hslToRGB(h: h, s: s, l: l)
        return .rgb(r, g, b)
    }

    /// Linearly interpolates between two colors in RGB space.
    ///
    /// - Parameters:
    ///   - a: The start color (phase = 0).
    ///   - b: The end color (phase = 1).
    ///   - phase: Blend factor in 0...1.
    public static func lerp(_ a: Color, _ b: Color, phase: Double) -> Color {
        let (ar, ag, ab) = a.toRGBDouble()
        let (br, bg, bb) = b.toRGBDouble()
        let t = max(0, min(1, phase))
        let r = UInt8((ar + (br - ar) * t).rounded())
        let g = UInt8((ag + (bg - ag) * t).rounded())
        let bCh = UInt8((ab + (bb - ab) * t).rounded())
        return .rgb(r, g, bCh)
    }
}

// MARK: - Private helpers

extension Color {
    /// Converts this color to (r, g, b) as Doubles in 0...255.
    private func toRGBDouble() -> (Double, Double, Double) {
        let (r, g, b) = toRGBComponents()
        return (Double(r), Double(g), Double(b))
    }

    /// Converts this color to its closest RGB representation.
    private func toRGBComponents() -> (UInt8, UInt8, UInt8) {
        switch self {
        case .rgb(let r, let g, let b):
            return (r, g, b)
        case .ansi(let c):
            return c.rgbApproximation
        case .xterm(let n):
            return xtermToRGB(n)
        }
    }

    /// Converts this color to HSL. Returns (h: 0–360, s: 0–1, l: 0–1).
    private func toHSL() -> (Double, Double, Double) {
        let (r, g, b) = toRGBComponents()
        return rgbToHSL(r: r, g: g, b: b)
    }
}

// MARK: - xterm 256-color → RGB

/// Converts an xterm 256-color index to an RGB triple.
///
/// - Color 0–15: ANSI 16-color approximations.
/// - Color 16–231: 6×6×6 color cube.
/// - Color 232–255: Grayscale ramp.
private func xtermToRGB(_ index: Int) -> (UInt8, UInt8, UInt8) {
    switch index {
    case 0 ..< 16:
        return ANSIColor(rawValue: index)!.rgbApproximation
    case 16 ..< 232:
        let i = index - 16
        let cubeSteps: [UInt8] = [0, 95, 135, 175, 215, 255]
        let b = cubeSteps[i % 6]
        let g = cubeSteps[(i / 6) % 6]
        let r = cubeSteps[(i / 36) % 6]
        return (r, g, b)
    default: // 232–255 grayscale ramp
        let level = UInt8(8 + (index - 232) * 10)
        return (level, level, level)
    }
}

// MARK: - HSL ↔ RGB

private func rgbToHSL(r: UInt8, g: UInt8, b: UInt8) -> (Double, Double, Double) {
    let rf = Double(r) / 255.0
    let gf = Double(g) / 255.0
    let bf = Double(b) / 255.0

    let cMax = max(rf, gf, bf)
    let cMin = min(rf, gf, bf)
    let delta = cMax - cMin

    let l = (cMax + cMin) / 2.0

    let s: Double
    if delta == 0 {
        s = 0
    } else {
        s = delta / (1.0 - abs(2.0 * l - 1.0))
    }

    let h: Double
    if delta == 0 {
        h = 0
    } else if cMax == rf {
        h = 60.0 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6))
    } else if cMax == gf {
        h = 60.0 * (((bf - rf) / delta) + 2)
    } else {
        h = 60.0 * (((rf - gf) / delta) + 4)
    }

    return (h < 0 ? h + 360 : h, s, l)
}

private func hslToRGB(h: Double, s: Double, l: Double) -> (UInt8, UInt8, UInt8) {
    // Clamp inputs so out-of-range values can't overflow UInt8 conversion.
    let sClamped = max(0, min(1, s))
    let lClamped = max(0, min(1, l))
    var hMod = h.truncatingRemainder(dividingBy: 360)
    if hMod < 0 { hMod += 360 }

    let c = (1.0 - abs(2.0 * lClamped - 1.0)) * sClamped
    let x = c * (1.0 - abs((hMod / 60.0).truncatingRemainder(dividingBy: 2) - 1.0))
    let m = lClamped - c / 2.0

    let (r1, g1, b1): (Double, Double, Double)
    switch hMod {
    case 0 ..< 60:   (r1, g1, b1) = (c, x, 0)
    case 60 ..< 120: (r1, g1, b1) = (x, c, 0)
    case 120 ..< 180:(r1, g1, b1) = (0, c, x)
    case 180 ..< 240:(r1, g1, b1) = (0, x, c)
    case 240 ..< 300:(r1, g1, b1) = (x, 0, c)
    default:          (r1, g1, b1) = (c, 0, x)
    }

    func clampByte(_ v: Double) -> UInt8 {
        UInt8(max(0, min(255, (v * 255).rounded())))
    }
    return (clampByte(r1 + m), clampByte(g1 + m), clampByte(b1 + m))
}

// MARK: - ANSI16 → RGB approximation

extension ANSIColor {
    /// Canonical xterm RGB approximation for this ANSI 16-color value.
    fileprivate var rgbApproximation: (UInt8, UInt8, UInt8) {
        switch self {
        case .black:        return (0x00, 0x00, 0x00)
        case .red:          return (0x80, 0x00, 0x00)
        case .green:        return (0x00, 0x80, 0x00)
        case .yellow:       return (0x80, 0x80, 0x00)
        case .blue:         return (0x00, 0x00, 0x80)
        case .magenta:      return (0x80, 0x00, 0x80)
        case .cyan:         return (0x00, 0x80, 0x80)
        case .white:        return (0xC0, 0xC0, 0xC0)
        case .brightBlack:  return (0x80, 0x80, 0x80)
        case .brightRed:    return (0xFF, 0x00, 0x00)
        case .brightGreen:  return (0x00, 0xFF, 0x00)
        case .brightYellow: return (0xFF, 0xFF, 0x00)
        case .brightBlue:   return (0x00, 0x00, 0xFF)
        case .brightMagenta:return (0xFF, 0x00, 0xFF)
        case .brightCyan:   return (0x00, 0xFF, 0xFF)
        case .brightWhite:  return (0xFF, 0xFF, 0xFF)
        }
    }
}
