import Markdown

// MARK: - Inline visitor (Result = String)

/// Walks inline markup nodes and produces an ANSI-styled String.
struct MarkdownInlineRenderer: MarkupVisitor {
    typealias Result = String

    let palette: Palette

    mutating func defaultVisit(_ markup: any Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    mutating func visitText(_ text: Text) -> String { text.string }

    mutating func visitStrong(_ strong: Strong) -> String {
        TextAttributes().bold().apply(to: defaultVisit(strong))
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        TextAttributes().italic().apply(to: defaultVisit(emphasis))
    }

    mutating func visitInlineCode(_ code: InlineCode) -> String {
        TextAttributes()
            .background(palette.surface)
            .foreground(palette.warning)
            .apply(to: " \(code.code) ")
    }

    mutating func visitLink(_ link: Link) -> String {
        var label = ""
        for child in link.children { label += visit(child) }
        guard let dest = link.destination, !dest.isEmpty else { return label }
        return Hyperlink.link(url: dest, text: label.isEmpty ? dest : label)
    }

    mutating func visitImage(_ image: Image) -> String {
        var alt = ""
        for child in image.children { alt += visit(child) }
        let label = alt.isEmpty ? (image.title ?? "image") : alt
        return TextAttributes().dim().apply(to: "[\(label)]")
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "\n" }
    mutating func visitInlineHTML(_ html: InlineHTML) -> String { "" }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        TextAttributes().strikethrough().apply(to: defaultVisit(strikethrough))
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        symbolLink.destination ?? defaultVisit(symbolLink)
    }
}
