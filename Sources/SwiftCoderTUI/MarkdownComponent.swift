import Markdown

// MARK: - MarkdownRenderer

/// Renders a Markdown string to ANSI-styled terminal output.
///
/// ```swift
/// let renderer = MarkdownRenderer()
/// print(renderer.render("# Hello\n\nThis is **bold** and *italic*."))
/// ```
public struct MarkdownRenderer {

    public let palette: Palette
    public let width: Int

    /// - Parameters:
    ///   - palette: Semantic color palette. Defaults to `DesignSystem.palette`.
    ///   - width:   Wrap column width. Defaults to 80.
    public init(palette: Palette? = nil, width: Int? = nil) {
        self.palette = palette ?? DesignSystem.palette
        self.width   = width   ?? 80
    }

    /// Parse `markdown` and return an ANSI-styled string ready for terminal output.
    public func render(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var walker = MarkdownBlockWalker(palette: palette, width: width)
        walker.visit(document)
        var result = walker.lines
        while result.last == "" { result.removeLast() }
        return result.joined(separator: "\n")
    }
}
