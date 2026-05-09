import Foundation

// MARK: - TruncatedText

/// ANSI-aware text truncation utility.
///
/// All measurements use ``VisibleWidth`` so multi-byte Unicode and ANSI styling
/// are accounted for correctly.
///
/// ```swift
/// let label = TruncatedText.truncate(longPath, toWidth: 40)
/// // → "/Users/alice/Projects/my-proj/src/Main…"
/// ```
public enum TruncatedText {

    // MARK: - Truncation

    /// Truncate `text` to `maxWidth` visible columns, appending `ellipsis` when cut.
    ///
    /// Only the text up to the first newline is considered (single-line truncation).
    /// Existing ANSI SGR sequences are preserved and their bytes are not counted toward
    /// the visible width.
    public static func truncate(
        _ text: String,
        toWidth maxWidth: Int,
        ellipsis: String = "…"
    ) -> String {
        guard maxWidth > 0 else { return "" }

        // Use only the first line.
        let firstLine: String
        if let nl = text.firstIndex(of: "\n") {
            firstLine = String(text[..<nl])
        } else {
            firstLine = text
        }

        let visible = VisibleWidth.measure(firstLine)
        guard visible > maxWidth else { return firstLine }

        let ellipsisWidth = VisibleWidth.measure(ellipsis)
        let target = max(0, maxWidth - ellipsisWidth)
        if target <= 0 { return String(ellipsis.prefix(maxWidth)) }

        var currentWidth = 0
        var truncateAt = firstLine.startIndex
        var index = firstLine.startIndex

        while index < firstLine.endIndex {
            // Skip ANSI escape sequences without counting their width.
            if let ansi = extractAnsi(in: firstLine, from: index) {
                index = ansi.next
                truncateAt = index
                continue
            }

            let charWidth = VisibleWidth.measure(String(firstLine[index]))
            if currentWidth + charWidth > target { break }
            currentWidth += charWidth
            index = firstLine.index(after: index)
            truncateAt = index
        }

        let prefix = String(firstLine[..<truncateAt])
        // Reset any open color codes before the ellipsis.
        return prefix + "\u{001B}[0m" + ellipsis
    }

    // MARK: - Render

    /// Render `text` as a single padded line of exactly `width` visible columns.
    ///
    /// - Parameters:
    ///   - text:      Source string (ANSI codes allowed).
    ///   - width:     Target visible width (total, including padding).
    ///   - paddingX:  Horizontal padding added on both sides.
    /// - Returns: A single `String` with the truncated/padded content.
    public static func render(
        _ text: String,
        width: Int,
        paddingX: Int = 0
    ) -> String {
        guard width > 0 else { return "" }
        let contentWidth = max(1, width - paddingX * 2)
        let truncated = truncate(text, toWidth: contentWidth)
        let leftPad = String(repeating: " ", count: max(0, paddingX))
        let visible = VisibleWidth.measure(truncated)
        let rightPadWidth = max(0, width - paddingX - visible)
        return leftPad + truncated + String(repeating: " ", count: rightPadWidth)
    }

    // MARK: - ANSI helpers

    /// Extract a single ANSI escape sequence starting at `index`, returning the
    /// sequence string and the index immediately after the sequence.
    /// Returns `nil` if `index` does not start an escape sequence.
    static func extractAnsi(
        in text: String,
        from index: String.Index
    ) -> (code: String, next: String.Index)? {
        guard text[index] == "\u{001B}" else { return nil }
        var current = text.index(after: index)
        guard current < text.endIndex else { return nil }
        while current < text.endIndex {
            let scalar = text[current].unicodeScalars.first!.value
            if scalar >= 0x40, scalar <= 0x7E {
                let next = text.index(after: current)
                return (String(text[index..<next]), next)
            }
            current = text.index(after: current)
        }
        return nil
    }
}
