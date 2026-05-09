import Markdown

// MARK: - Block walker (Result = Void, appends to `lines`)

struct MarkdownBlockWalker: MarkupVisitor {
    typealias Result = Void

    let palette: Palette
    let width: Int
    var lines: [String] = []

    init(palette: Palette, width: Int) {
        self.palette = palette
        self.width   = width
    }

    // Default: descend into children (handles Document and any unrecognised node).
    mutating func defaultVisit(_ markup: any Markup) {
        for child in markup.children { visit(child) }
    }

    // MARK: Headings

    mutating func visitHeading(_ heading: Heading) {
        let text = inline(heading)
        let styled: String
        switch heading.level {
        case 1:  styled = TextAttributes().bold().foreground(palette.accent).apply(to: text)
        case 2:  styled = TextAttributes().bold().apply(to: text)
        default: styled = TextAttributes().bold().dim().apply(to: text)
        }
        lines.append(styled)
        lines.append("")
    }

    // MARK: Paragraph

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let text    = inline(paragraph)
        let wrapped = AnsiWrapping.wrap(text, width: width, breakOnWords: true)
        lines.append(contentsOf: wrapped)
        lines.append("")
    }

    // MARK: Code block

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let bar  = TextAttributes().foreground(palette.muted).apply(to: "│ ")
        var code = codeBlock.code
        if code.hasSuffix("\n") { code = String(code.dropLast()) }
        for line in code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            lines.append("  " + bar + line)
        }
        lines.append("")
    }

    // MARK: Block quote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let prefix = TextAttributes().foreground(palette.muted).apply(to: "┃ ")
        var inner  = MarkdownBlockWalker(palette: palette, width: max(20, width - 2))
        for child in blockQuote.children { inner.visit(child) }
        var innerLines = inner.lines
        while innerLines.last == "" { innerLines.removeLast() }
        for line in innerLines { lines.append(prefix + line) }
        lines.append("")
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ list: UnorderedList) {
        lines.append(contentsOf: listFormatter.renderUnorderedList(list))
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        lines.append(contentsOf: listFormatter.renderOrderedList(list))
    }

    // MARK: Thematic break

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let rule = TextAttributes().foreground(palette.border)
            .apply(to: String(repeating: "─", count: width))
        lines.append(rule)
        lines.append("")
    }

    // MARK: Table

    mutating func visitTable(_ table: Table) {
        lines.append(contentsOf: tableFormatter.renderTable(table))
    }

    // MARK: HTML (skip)

    mutating func visitHTMLBlock(_ html: HTMLBlock) { /* intentionally empty */ }

    // MARK: - Private helpers

    /// Render inline children of `markup` to an ANSI-styled String.
    private func inline(_ markup: any Markup) -> String {
        var renderer = MarkdownInlineRenderer(palette: palette)
        var out = ""
        for child in markup.children { out += renderer.visit(child) }
        return out
    }

    private var listFormatter: MarkdownListFormatter {
        MarkdownListFormatter(
            width: width,
            inline: inline,
            renderNestedBlock: { child, innerWidth in
                var inner = MarkdownBlockWalker(palette: palette, width: innerWidth)
                inner.visit(child)
                return inner.lines
            }
        )
    }

    private var tableFormatter: MarkdownTableFormatter {
        MarkdownTableFormatter(
            palette: palette,
            width: width,
            inline: inline
        )
    }
}
