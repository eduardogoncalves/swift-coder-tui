/// A composable, immutable builder for ANSI SGR (Select Graphic Rendition) text attributes.
///
/// Usage examples:
/// ```swift
/// // TextAttributes.plain.apply(to: "hello") == "hello"
/// // TextAttributes().bold().apply(to: "hi") == "\u{1B}[1mhi\u{1B}[0m"
/// // TextAttributes().bold().italic().foreground(.ansi(.red)).apply(to: "x")
/// //   == "\u{1B}[1;3;31mx\u{1B}[0m"
/// // TextAttributes().foreground(.xterm(200)).apply(to: "x")
/// //   == "\u{1B}[38;5;200mx\u{1B}[0m"
/// // TextAttributes().foreground(.rgb(255, 128, 0)).apply(to: "x")
/// //   == "\u{1B}[38;2;255;128;0mx\u{1B}[0m"
/// ```
public struct TextAttributes: Sendable, Hashable {

    // MARK: - Storage

    private var sgrFlags: SGRFlags
    private var fg: Color?
    private var bg: Color?

    // MARK: - SGR flag bits

    private struct SGRFlags: OptionSet, Sendable, Hashable {
        let rawValue: UInt8
        static let bold          = SGRFlags(rawValue: 1 << 0)
        static let dim           = SGRFlags(rawValue: 1 << 1)
        static let italic        = SGRFlags(rawValue: 1 << 2)
        static let underline     = SGRFlags(rawValue: 1 << 3)
        static let strikethrough = SGRFlags(rawValue: 1 << 4)
    }

    // MARK: - Init

    public init() {
        sgrFlags = []
        fg = nil
        bg = nil
    }

    private init(sgrFlags: SGRFlags, fg: Color?, bg: Color?) {
        self.sgrFlags = sgrFlags
        self.fg = fg
        self.bg = bg
    }

    // MARK: - Static convenience

    /// No-op attributes; `apply(to:)` returns the text unchanged.
    public static let plain = TextAttributes()

    // MARK: - Fluent setters

    public func bold()          -> TextAttributes { setting(.bold) }
    public func dim()           -> TextAttributes { setting(.dim) }
    public func italic()        -> TextAttributes { setting(.italic) }
    public func underline()     -> TextAttributes { setting(.underline) }
    public func strikethrough() -> TextAttributes { setting(.strikethrough) }

    public func foreground(_ color: Color) -> TextAttributes {
        TextAttributes(sgrFlags: sgrFlags, fg: color, bg: bg)
    }

    public func background(_ color: Color) -> TextAttributes {
        TextAttributes(sgrFlags: sgrFlags, fg: fg, bg: color)
    }

    // MARK: - Public accessors
    //
    // These read-only accessors let other modules (e.g. `FrameBuffer`) inspect
    // an attribute set without reverse-engineering its `openSequence` string.

    public var isBold:          Bool { sgrFlags.contains(.bold) }
    public var isDim:           Bool { sgrFlags.contains(.dim) }
    public var isItalic:        Bool { sgrFlags.contains(.italic) }
    public var isUnderline:     Bool { sgrFlags.contains(.underline) }
    public var isStrikethrough: Bool { sgrFlags.contains(.strikethrough) }

    public var foregroundColor: Color? { fg }
    public var backgroundColor: Color? { bg }

    // MARK: - SGR sequences

    /// The opening SGR escape sequence combining all active attributes.
    /// Empty string when no attributes are set.
    public var openSequence: String {
        var params: [String] = []

        if sgrFlags.contains(.bold)          { params.append("1") }
        if sgrFlags.contains(.dim)           { params.append("2") }
        if sgrFlags.contains(.italic)        { params.append("3") }
        if sgrFlags.contains(.underline)     { params.append("4") }
        if sgrFlags.contains(.strikethrough) { params.append("9") }

        if let color = fg { params.append(contentsOf: color.sgrParameters(isForeground: true)) }
        if let color = bg { params.append(contentsOf: color.sgrParameters(isForeground: false)) }

        return SGR.encode(params)
    }

    /// The SGR reset sequence `ESC[0m`, or empty string when no attributes are set.
    public var resetSequence: String {
        openSequence.isEmpty ? "" : SGR.reset
    }

    /// Wraps `text` with the open SGR sequence and a reset.
    /// Returns `text` unchanged when no attributes are active.
    public func apply(to text: String) -> String {
        let open = openSequence
        guard !open.isEmpty else { return text }
        return "\(open)\(text)\(SGR.reset)"
    }

    // MARK: - Private helpers

    private func setting(_ flag: SGRFlags) -> TextAttributes {
        TextAttributes(sgrFlags: sgrFlags.union(flag), fg: fg, bg: bg)
    }
}
