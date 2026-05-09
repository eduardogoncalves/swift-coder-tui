// SGR.swift
//
// Single source of truth for ANSI Select Graphic Rendition (SGR) sequences.
//
// Background: Before this module existed, five separate emitters built SGR
// strings independently — `Color.foregroundSGR`/`backgroundSGR`,
// `TextAttributes.openSequence`, `FrameBuffer.SGRState.sgrSequence`,
// `DiffRenderer.SGRState`, and `AnsiCodeTracker.activeOpenSequence`. They
// drifted apart over time (different parameter ordering for combined codes,
// inconsistent reset strategies, and a particularly fragile string-parsing
// hack in FrameBuffer that reverse-engineered TextAttributes' opaque output).
//
// Everything here is internal-by-default; only `SGR.encode` and the public
// `Color.sgrParameters(isForeground:)` extension are part of the public API.

// MARK: - SGR encoding

/// Namespace for ANSI SGR (Select Graphic Rendition) sequence construction.
public enum SGR {
    /// CSI prefix: `ESC [`.
    public static let csi = "\u{1B}["

    /// Full reset: `ESC [ 0 m`.
    public static let reset = "\u{1B}[0m"

    /// Wrap a list of SGR parameter strings into a single CSI sequence.
    ///
    /// Example: `SGR.encode(["1", "31"])` → `"\u{1B}[1;31m"`.
    /// An empty parameter list yields the implicit-reset `"\u{1B}[m"`, which is
    /// almost certainly a caller bug — return `""` instead so consumers that
    /// build conditional sequences don't accidentally emit a reset.
    public static func encode(_ parameters: [String]) -> String {
        guard !parameters.isEmpty else { return "" }
        return "\(csi)\(parameters.joined(separator: ";"))m"
    }
}

// MARK: - Color → SGR parameters

extension Color {
    /// SGR parameter components for this color, suitable for embedding inside
    /// a combined CSI sequence (see ``SGR/encode(_:)``).
    ///
    /// - For ANSI 16-color values the result is a single token like `"31"`.
    /// - For xterm-256 it expands to three tokens: `["38", "5", "N"]`.
    /// - For RGB it expands to five tokens: `["38", "2", "R", "G", "B"]`.
    public func sgrParameters(isForeground: Bool) -> [String] {
        switch self {
        case .ansi(let c):
            let base = isForeground
                ? (c.rawValue < 8 ? 30 : 82)
                : (c.rawValue < 8 ? 40 : 92)
            return ["\(base + c.rawValue)"]
        case .xterm(let n):
            return [isForeground ? "38" : "48", "5", "\(n)"]
        case .rgb(let r, let g, let b):
            return [isForeground ? "38" : "48", "2", "\(r)", "\(g)", "\(b)"]
        }
    }
}

// MARK: - Shared cell-style snapshot

/// Visual attributes of a terminal cell, used by buffer renderers (`FrameBuffer`,
/// `DiffRenderer`) to track current vs. desired SGR state.
///
/// This type was previously duplicated as `private struct SGRState` in two
/// files with subtly different shapes; consolidating it here removes the
/// drift risk.
struct CellStyle: Equatable {
    var foreground: Color?
    var background: Color?
    var bold: Bool
    var italic: Bool
    var underline: Bool

    init(
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }

    static let empty = CellStyle()

    /// Build a `CellStyle` from a `Cell`'s style attributes.
    init(_ cell: Cell) {
        self.init(
            foreground: cell.foreground,
            background: cell.background,
            bold: cell.bold,
            italic: cell.italic,
            underline: cell.underline)
    }

    /// Encode this style as a single CSI sequence that begins with a reset.
    ///
    /// This is the safe transition strategy used by `FrameBuffer.render()`
    /// (always-reset-then-apply, correct regardless of prior state).
    /// `DiffRenderer` uses a more frugal transition that diffs individual
    /// attributes — see ``transitionParameters(from:to:)``.
    func resetEncodedSequence() -> String {
        var params = ["0"]
        if bold      { params.append("1") }
        if italic    { params.append("3") }
        if underline { params.append("4") }
        if let fg = foreground { params.append(contentsOf: fg.sgrParameters(isForeground: true)) }
        if let bg = background { params.append(contentsOf: bg.sgrParameters(isForeground: false)) }
        return SGR.encode(params)
    }
}
