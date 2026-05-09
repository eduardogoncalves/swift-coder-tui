import Foundation

// MARK: - StreamFormatter

/// Tracks fenced code-block state as text lines are committed during streaming,
/// and applies ANSI styling so code and diff blocks are visually distinguished.
///
/// Usage (called by ``Renderer`` as each line is committed):
/// ```swift
/// let formatted = streamFormatter.format(line)
/// contentLines.append(formatted)
/// ```
public final class StreamFormatter {

    // MARK: State

    private var inCodeBlock = false
    private var language: String = ""

    // MARK: Public API

    /// Format a single line. Maintains internal fence state across calls.
    public func format(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Fence detection: trimmed line starts with ```
        if trimmed.hasPrefix("```") {
            if !inCodeBlock {
                // Opening fence
                inCodeBlock = true
                language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let label = language.isEmpty ? "code" : language
                return "\(DesignSystem.darkGray)  ╭── \(label) ──\(DesignSystem.reset)"
            } else {
                // Closing fence
                inCodeBlock = false
                language = ""
                return "\(DesignSystem.darkGray)  ╰───────────\(DesignSystem.reset)"
            }
        }

        guard inCodeBlock else { return applyInlineMarkdown(line) }

        // Inside a code block
        let indent = "  "
        if language == "diff" {
            return styleDiffLine(indent + line)
        } else {
            return "\(DesignSystem.brightCyan)\(indent)\(line)\(DesignSystem.reset)"
        }
    }

    /// Format a single line without mutating fence state.
    ///
    /// The footer's "live stream preview" can redraw the same partial line many
    /// times before it is committed. Using the stateful `format(_:)` there would
    /// repeatedly toggle fence state on lines like ``` and corrupt open/close
    /// box rendering once the line is finally committed.
    public func formatPreview(_ line: String) -> String {
        let snapshot = (inCodeBlock, language)
        let rendered = format(line)
        inCodeBlock = snapshot.0
        language = snapshot.1
        return rendered
    }

    /// Reset fence state (call when a new stream starts).
    public func reset() {
        inCodeBlock = false
        language = ""
    }

    // MARK: Inline markdown

    private func applyInlineMarkdown(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Horizontal rules
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            return "\(DesignSystem.darkGray)────────────────────────────────────────\(DesignSystem.reset)"
        }

        // ATX headings
        if trimmed.hasPrefix("### ") {
            let text = applyInlineStyles(String(trimmed.dropFirst(4)))
            return "\(DesignSystem.brightWhite)\u{001B}[1m\(text)\(DesignSystem.reset)"
        }
        if trimmed.hasPrefix("## ") {
            let text = applyInlineStyles(String(trimmed.dropFirst(3)))
            return "\(DesignSystem.brightWhite)\u{001B}[1m\(text)\(DesignSystem.reset)"
        }
        if trimmed.hasPrefix("# ") {
            let text = applyInlineStyles(String(trimmed.dropFirst(2)))
            return "\u{001B}[1m\u{001B}[4m\(text)\(DesignSystem.reset)"
        }

        // Unordered lists — preserve leading indent
        let leadingSpaces = line.prefix(while: { $0 == " " })
        let rest = String(line.dropFirst(leadingSpaces.count))
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") {
            let content = applyInlineStyles(String(rest.dropFirst(2)))
            return "\(leadingSpaces)  • \(content)"
        }

        // Plain line — apply inline styles only
        return applyInlineStyles(line)
    }

    /// Replace `**bold**`, `*italic*`, and `` `code` `` patterns inside a string.
    private func applyInlineStyles(_ text: String) -> String {
        var result = text
        result = replaceMarkdownPattern(result,
                                        open: "**", close: "**",
                                        prefix: "\u{001B}[1m", suffix: DesignSystem.reset)
        result = replaceMarkdownPattern(result,
                                        open: "*",  close: "*",
                                        prefix: "\u{001B}[3m", suffix: DesignSystem.reset)
        result = replaceMarkdownPattern(result,
                                        open: "`",  close: "`",
                                        prefix: "\(DesignSystem.yellow)",
                                        suffix: DesignSystem.reset)
        return result
    }

    /// Replace all non-overlapping `open...close` marker pairs with ANSI-styled content.
    private func replaceMarkdownPattern(_ text: String,
                                        open: String, close: String,
                                        prefix: String, suffix: String) -> String {
        var result = ""
        var remaining = text[text.startIndex...]
        let openLen  = open.count
        let closeLen = close.count
        while !remaining.isEmpty {
            guard let openRange = remaining.range(of: open) else {
                result += remaining; break
            }
            let afterOpen = remaining[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: close) else {
                result += remaining; break
            }
            result += remaining[remaining.startIndex..<openRange.lowerBound]
            result += prefix + afterOpen[afterOpen.startIndex..<closeRange.lowerBound] + suffix
            remaining = afterOpen[closeRange.upperBound...]
            _ = openLen + closeLen  // suppress unused-variable warnings
        }
        return result
    }

    // MARK: Private helpers

    private func styleDiffLine(_ line: String) -> String {
        // Strip the indent prefix for inspection, then apply to the full indented line
        let content = String(line.dropFirst(2)) // remove the 2-space indent we added
        if content.hasPrefix("+++") || content.hasPrefix("---") {
            return "\(DesignSystem.dim)\(line)\(DesignSystem.reset)"
        } else if content.hasPrefix("+") {
            return "\(DesignSystem.green)\(line)\(DesignSystem.reset)"
        } else if content.hasPrefix("-") {
            return "\(DesignSystem.red)\(line)\(DesignSystem.reset)"
        } else if content.hasPrefix("@@") {
            return "\(DesignSystem.brightCyan)\(line)\(DesignSystem.reset)"
        } else {
            return line
        }
    }
}
