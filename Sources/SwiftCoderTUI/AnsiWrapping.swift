/// ANSI-aware text wrapping that preserves SGR colour codes across line breaks.
///
/// Example – hard wrap:
/// ```
/// let lines = AnsiWrapping.wrap("\u{1B}[31mHello, world!\u{1B}[0m", width: 7)
/// // ["\u{1B}[31mHello, \u{1B}[0m", "\u{1B}[31mworld!\u{1B}[0m"]
/// ```
///
/// Example – word wrap:
/// ```
/// let lines = AnsiWrapping.wrap("\u{1B}[1mfoo bar baz\u{1B}[0m", width: 7, breakOnWords: true)
/// // ["\u{1B}[1mfoo bar\u{1B}[0m", "\u{1B}[1mbaz\u{1B}[0m"]
/// ```

// MARK: - AnsiCodeTracker

/// Stateful tracker for SGR (Select Graphic Rendition) codes in an ANSI escape stream.
///
/// Feed it chunks of text as they arrive via `consume(_:)`. Query `activeOpenSequence`
/// to get the minimal SGR string needed to re-establish the current style on a new line.
public struct AnsiCodeTracker {

    private var bold          = false
    private var dim           = false
    private var italic        = false
    private var underline     = false
    private var blink         = false
    private var reverse       = false
    private var strikethrough = false

    private enum Color: Equatable {
        case standard(Int)       // 30-37, 39, 40-47, 49, 90-97, 100-107
        case index256(Int)       // 38;5;N  /  48;5;N
        case rgb(Int, Int, Int)  // 38;2;R;G;B  /  48;2;R;G;B
    }

    private var fgColor: Color?
    private var bgColor: Color?

    public init() {}

    // MARK: Public API

    /// `true` when at least one SGR attribute is currently active.
    public var hasActiveStyle: Bool {
        bold || dim || italic || underline || blink || reverse || strikethrough
            || fgColor != nil || bgColor != nil
    }

    /// Scan `chunk` for CSI SGR sequences and update internal state accordingly.
    /// Non-SGR content is ignored.
    public mutating func consume(_ chunk: String) {
        let sv = chunk.unicodeScalars
        var si = sv.startIndex
        while si < sv.endIndex {
            let sc = sv[si]
            guard sc.value == 0x1B else { si = sv.index(after: si); continue }

            let afterEsc = sv.index(after: si)
            guard afterEsc < sv.endIndex else { break }
            let next = sv[afterEsc]

            var end = sv.index(after: afterEsc)

            if next.value == 0x5B {  // CSI: ESC [
                var paramStr = ""
                var terminator: UInt32 = 0
                while end < sv.endIndex {
                    let c = sv[end]
                    end = sv.index(after: end)
                    if (0x40...0x7E).contains(c.value) { terminator = c.value; break }
                    paramStr.unicodeScalars.append(c)
                }
                if terminator == 0x6D { applyParams(paramStr) }  // 'm'
            } else {
                // Other ESC sequence: skip second byte only
                end = sv.index(after: afterEsc)
            }
            si = end
        }
    }

    /// Clear all tracked SGR state.
    public mutating func reset() {
        bold = false; dim = false; italic = false; underline = false
        blink = false; reverse = false; strikethrough = false
        fgColor = nil; bgColor = nil
    }

    /// The minimal CSI SGR string needed to re-establish the current style on a fresh line,
    /// or an empty string when no style is active.
    public var activeOpenSequence: String {
        guard hasActiveStyle else { return "" }
        var parts: [String] = []
        if bold          { parts.append("1") }
        if dim           { parts.append("2") }
        if italic        { parts.append("3") }
        if underline     { parts.append("4") }
        if blink         { parts.append("5") }
        if reverse       { parts.append("7") }
        if strikethrough { parts.append("9") }
        switch fgColor {
        case .none: break
        case .standard(let n):        parts.append("\(n)")
        case .index256(let n):        parts.append(contentsOf: ["38", "5", "\(n)"])
        case .rgb(let r, let g, let b): parts.append(contentsOf: ["38", "2", "\(r)", "\(g)", "\(b)"])
        }
        switch bgColor {
        case .none: break
        case .standard(let n):        parts.append("\(n)")
        case .index256(let n):        parts.append(contentsOf: ["48", "5", "\(n)"])
        case .rgb(let r, let g, let b): parts.append(contentsOf: ["48", "2", "\(r)", "\(g)", "\(b)"])
        }
        return SGR.encode(parts)
    }

    // MARK: Private

    private mutating func applyParams(_ params: String) {
        guard !params.isEmpty else { reset(); return }

        let parts = params
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) }  // [Int?]

        var i = 0
        while i < parts.count {
            guard let code = parts[i] else { i += 1; continue }
            switch code {
            case 0:  reset()
            case 1:  bold = true
            case 2:  dim = true
            case 3:  italic = true
            case 4:  underline = true
            case 5:  blink = true
            case 7:  reverse = true
            case 9:  strikethrough = true
            case 22: bold = false; dim = false
            case 23: italic = false
            case 24: underline = false
            case 25: blink = false
            case 27: reverse = false
            case 29: strikethrough = false
            case 30...37:
                fgColor = .standard(code)
            case 38:
                if i + 1 < parts.count, let sub = parts[i + 1] {
                    if sub == 5, i + 2 < parts.count, let n = parts[i + 2] {
                        fgColor = .index256(n); i += 2
                    } else if sub == 2, i + 4 < parts.count,
                              let r = parts[i + 2], let g = parts[i + 3], let b = parts[i + 4] {
                        fgColor = .rgb(r, g, b); i += 4
                    }
                }
            case 39: fgColor = nil
            case 40...47:
                bgColor = .standard(code)
            case 48:
                if i + 1 < parts.count, let sub = parts[i + 1] {
                    if sub == 5, i + 2 < parts.count, let n = parts[i + 2] {
                        bgColor = .index256(n); i += 2
                    } else if sub == 2, i + 4 < parts.count,
                              let r = parts[i + 2], let g = parts[i + 3], let b = parts[i + 4] {
                        bgColor = .rgb(r, g, b); i += 4
                    }
                }
            case 49:      bgColor = nil
            case 90...97:   fgColor = .standard(code)
            case 100...107: bgColor = .standard(code)
            default: break
            }
            i += 1
        }
    }
}

// MARK: - AnsiWrapping

/// Utilities for wrapping ANSI-styled text to a fixed column width.
public enum AnsiWrapping {

    /// Split `text` into lines of at most `width` visible columns using hard (character-level) breaks.
    /// Active SGR styles are closed with `ESC[0m` at the end of each broken line and re-opened
    /// with the minimal restore sequence at the start of the continuation line.
    public static func wrap(_ text: String, width: Int) -> [String] {
        wrap(text, width: width, breakOnWords: false)
    }

    /// Split `text` into lines of at most `width` visible columns.
    ///
    /// - Parameters:
    ///   - text:         Input text, may contain CSI/OSC escape sequences.
    ///   - width:        Maximum visible column count per line (must be > 0).
    ///   - breakOnWords: When `true`, prefer breaking on whitespace; falls back to a
    ///                   hard break only when a single token exceeds `width`.
    public static func wrap(_ text: String, width: Int, breakOnWords: Bool) -> [String] {
        guard width > 0 else { return text.isEmpty ? [] : [text] }
        return breakOnWords ? wordWrap(text, width: width) : hardWrap(text, width: width)
    }

    // MARK: - Internal token type

    private enum Token {
        case char(Character, width: Int)
        case ansi(String)
        case newline
    }

    // MARK: - Tokenizer

    /// Parse `text` into a flat list of tokens: visible grapheme clusters, ANSI/OSC
    /// escape sequences, and newlines. The tokenizer walks the scalar view to detect
    /// escape sequences, then maps character-boundary positions to full grapheme clusters.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let sv = text.unicodeScalars
        var si = sv.startIndex

        while si < sv.endIndex {
            let sc = sv[si]

            if sc.value == 0x1B {  // ESC
                let afterEsc = sv.index(after: si)
                guard afterEsc < sv.endIndex else { break }
                let next = sv[afterEsc]
                var end = sv.index(after: afterEsc)

                if next.value == 0x5B {  // CSI: ESC [
                    while end < sv.endIndex {
                        let c = sv[end]
                        end = sv.index(after: end)
                        if (0x40...0x7E).contains(c.value) { break }
                    }
                } else if next.value == 0x5D {  // OSC: ESC ]
                    while end < sv.endIndex {
                        let c = sv[end]
                        end = sv.index(after: end)
                        if c.value == 0x07 { break }
                        if c.value == 0x1B {
                            if end < sv.endIndex { end = sv.index(after: end) }
                            break
                        }
                    }
                }
                // else: two-byte ESC sequence – `end` already points past the second byte
                tokens.append(.ansi(String(sv[si..<end])))
                si = end

            } else if sc.value == 0x0A {  // LF newline
                tokens.append(.newline)
                si = sv.index(after: si)

            } else {
                // Map the scalar index to a Character index so we capture the full
                // grapheme cluster (base + combining marks, ZWJ emoji sequences, etc.).
                if let charIdx = si.samePosition(in: text) {
                    let ch = text[charIdx]
                    let w = VisibleWidth.measure(String(ch))
                    tokens.append(.char(ch, width: w))
                    let nextCharIdx = text.index(after: charIdx)
                    si = nextCharIdx.samePosition(in: sv) ?? sv.endIndex
                } else {
                    // Scalar is in the middle of a grapheme already emitted – skip.
                    si = sv.index(after: si)
                }
            }
        }
        return tokens
    }

    // MARK: - Hard wrap

    private static func hardWrap(_ text: String, width: Int) -> [String] {
        var lines:        [String]         = []
        var currentLine:   String          = ""
        var currentWidth:  Int             = 0
        var tracker:       AnsiCodeTracker = AnsiCodeTracker()
        var pendingOpener: String          = ""  // deferred until first content on a new line

        // Emit `s` to the current line, prepending any deferred opener first.
        func emit(_ s: String) { if !pendingOpener.isEmpty { currentLine = pendingOpener; pendingOpener = "" }; currentLine += s }

        func flushLine() {
            if tracker.hasActiveStyle { currentLine += "\u{1B}[0m" }
            lines.append(currentLine)
            pendingOpener = tracker.activeOpenSequence
            currentLine   = ""
            currentWidth  = 0
        }

        for token in tokenize(text) {
            switch token {
            case .newline:
                flushLine()

            case .ansi(let s):
                tracker.consume(s)
                emit(s)

            case .char(let ch, let w):
                if currentWidth > 0 && currentWidth + w > width {
                    flushLine()
                }
                emit(String(ch))
                currentWidth += w
            }
        }

        // Final line (may be empty when text ends with a newline)
        if !currentLine.isEmpty || !pendingOpener.isEmpty {
            // Only push a non-empty visible line.
            if !currentLine.isEmpty {
                if tracker.hasActiveStyle { currentLine += "\u{1B}[0m" }
                lines.append(currentLine)
            }
        }

        return lines
    }

    // MARK: - Word wrap

    private static func wordWrap(_ text: String, width: Int) -> [String] {
        var lines:        [String]         = []
        var currentLine:   String          = ""
        var currentWidth:  Int             = 0
        var tracker:       AnsiCodeTracker = AnsiCodeTracker()
        var pendingOpener: String          = ""

        // Word-accumulation buffers
        var wordBuf:   [Token] = []  // tokens forming the in-progress word
        var wordWidth: Int     = 0
        var inWord:    Bool    = false

        // Whitespace buffer (between words)
        var spaceBuf:   String = ""
        var spaceWidth: Int    = 0

        func emit(_ s: String) {
            if !pendingOpener.isEmpty { currentLine = pendingOpener; pendingOpener = "" }
            currentLine += s
        }

        func flushLine() {
            if tracker.hasActiveStyle { currentLine += "\u{1B}[0m" }
            lines.append(currentLine)
            pendingOpener = tracker.activeOpenSequence
            currentLine   = ""
            currentWidth  = 0
        }

        // Commit the accumulated word to `currentLine`, breaking if it doesn't fit.
        func commitWord() {
            guard !wordBuf.isEmpty else { return }

            let needBreak = currentWidth > 0 && currentWidth + spaceWidth + wordWidth > width

            if needBreak {
                flushLine()
                spaceBuf  = ""; spaceWidth = 0
            } else {
                // Add pending spaces (only when there's already content on the line)
                if currentWidth > 0 {
                    emit(spaceBuf)
                    currentWidth += spaceWidth
                }
                spaceBuf  = ""; spaceWidth = 0
            }

            // Emit word tokens, hard-breaking within the word if it is wider than `width`.
            for tok in wordBuf {
                switch tok {
                case .char(let ch, let w):
                    if currentWidth > 0 && currentWidth + w > width {
                        flushLine()
                    }
                    emit(String(ch))
                    currentWidth += w
                case .ansi(let s):
                    tracker.consume(s)
                    emit(s)
                case .newline:
                    break  // newlines are not buffered into words
                }
            }

            wordBuf   = []
            wordWidth = 0
            inWord    = false
        }

        for token in tokenize(text) {
            switch token {

            case .newline:
                commitWord()
                flushLine()
                spaceBuf = ""; spaceWidth = 0

            case .ansi(let s):
                if inWord {
                    // Buffer; tracker will be updated when the word is committed.
                    wordBuf.append(.ansi(s))
                } else {
                    // Between words: emit immediately (zero-width, doesn't affect layout).
                    tracker.consume(s)
                    emit(s)
                }

            case .char(let ch, let w) where ch == " " || ch == "\t":
                // Whitespace ends the current word.
                if inWord { commitWord() }
                spaceBuf.append(ch)
                spaceWidth += w

            case .char(let ch, let w):
                if !inWord { inWord = true }
                wordBuf.append(.char(ch, width: w))
                wordWidth += w
            }
        }

        commitWord()

        if !currentLine.isEmpty {
            if tracker.hasActiveStyle { currentLine += "\u{1B}[0m" }
            lines.append(currentLine)
        }

        return lines
    }
}
