/// Box-drawing character sets for rendering styled terminal borders.
public enum BoxStyle: CaseIterable {
    case single, double, rounded, heavy, dashed, ascii, none

    public var topLeft:     String { chars.0 }
    public var topRight:    String { chars.1 }
    public var bottomLeft:  String { chars.2 }
    public var bottomRight: String { chars.3 }
    public var horizontal:  String { chars.4 }
    public var vertical:    String { chars.5 }
    public var teeLeft:     String { chars.6 }
    public var teeRight:    String { chars.7 }

    // (topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical, teeLeft, teeRight)
    private var chars: (String, String, String, String, String, String, String, String) {
        switch self {
        case .single:  return ("┌", "┐", "└", "┘", "─", "│", "├", "┤")
        case .double:  return ("╔", "╗", "╚", "╝", "═", "║", "╠", "╣")
        case .rounded: return ("╭", "╮", "╰", "╯", "─", "│", "├", "┤")
        case .heavy:   return ("┏", "┓", "┗", "┛", "━", "┃", "┣", "┫")
        case .dashed:  return ("┌", "┐", "└", "┘", "╌", "╎", "├", "┤")
        case .ascii:   return ("+", "+", "+", "+", "-", "|", "+", "+")
        case .none:    return (" ", " ", " ", " ", " ", " ", " ", " ")
        }
    }
}

/// Renders hollow boxes using a given `BoxStyle`.
public struct BoxRenderer {

    /// Returns `height` lines representing an empty box of the given dimensions.
    ///
    /// - Parameters:
    ///   - width: Total width including borders (must be ≥ 2).
    ///   - height: Total height including borders (must be ≥ 2).
    ///   - style: The border character set.
    ///   - attributes: Optional ANSI text attributes applied to every line.
    public static func draw(
        width: Int,
        height: Int,
        style: BoxStyle,
        attributes: TextAttributes? = nil
    ) -> [String] {
        guard width >= 2, height >= 2 else {
            return Array(repeating: "", count: max(0, height))
        }

        let innerWidth = width - 2
        let topLine = style.topLeft    + String(repeating: style.horizontal, count: innerWidth) + style.topRight
        let midLine = style.vertical   + String(repeating: " ", count: innerWidth)               + style.vertical
        let botLine = style.bottomLeft + String(repeating: style.horizontal, count: innerWidth) + style.bottomRight

        var lines = [topLine]
        for _ in 0..<(height - 2) { lines.append(midLine) }
        lines.append(botLine)

        return apply(attributes, to: lines)
    }

    /// Wraps `content` lines in a styled box with uniform padding on all sides.
    ///
    /// Column math uses `VisibleWidth.measure` so ANSI-styled content is measured correctly.
    ///
    /// - Parameters:
    ///   - content: The lines to wrap. May contain ANSI escape sequences.
    ///   - style: The border character set.
    ///   - padding: Number of blank columns/rows between content and border (default 1).
    ///   - attributes: Optional ANSI text attributes applied to the border lines.
    public static func draw(
        content: [String],
        style: BoxStyle,
        padding: Int = 1,
        attributes: TextAttributes? = nil
    ) -> [String] {
        let maxContentWidth = content.map { VisibleWidth.measure($0) }.max() ?? 0
        let innerWidth = maxContentWidth + 2 * padding

        let topLine   = style.topLeft    + String(repeating: style.horizontal, count: innerWidth) + style.topRight
        let botLine   = style.bottomLeft + String(repeating: style.horizontal, count: innerWidth) + style.bottomRight
        let emptyLine = style.vertical   + String(repeating: " ", count: innerWidth)               + style.vertical
        let pad       = String(repeating: " ", count: padding)

        var lines = [topLine]
        for _ in 0..<padding { lines.append(emptyLine) }

        for contentLine in content {
            let visWidth  = VisibleWidth.measure(contentLine)
            let trailing  = String(repeating: " ", count: maxContentWidth - visWidth + padding)
            lines.append(style.vertical + pad + contentLine + trailing + style.vertical)
        }

        for _ in 0..<padding { lines.append(emptyLine) }
        lines.append(botLine)

        return apply(attributes, to: lines)
    }

    // MARK: - Private helpers

    private static func apply(_ attributes: TextAttributes?, to lines: [String]) -> [String] {
        guard let attrs = attributes else { return lines }
        return lines.map { attrs.apply(to: $0) }
    }
}
