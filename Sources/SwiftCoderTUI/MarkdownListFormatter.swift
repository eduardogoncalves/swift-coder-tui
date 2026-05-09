import Markdown

struct MarkdownListFormatter {
    let width: Int
    let inline: (any Markup) -> String
    let renderNestedBlock: (any Markup, Int) -> [String]

    func renderUnorderedList(_ list: UnorderedList) -> [String] {
        var result: [String] = []
        for child in list.children {
            if let item = child as? ListItem {
                appendListItem(item, bullet: "  • ", to: &result)
            }
        }
        result.append("")
        return result
    }

    func renderOrderedList(_ list: OrderedList) -> [String] {
        var result: [String] = []
        var n = 1
        for child in list.children {
            if let item = child as? ListItem {
                appendListItem(item, bullet: "  \(n). ", to: &result)
                n += 1
            }
        }
        result.append("")
        return result
    }

    private func appendListItem(_ item: ListItem, bullet: String, to output: inout [String]) {
        // Use VisibleWidth so non-ASCII bullets ("  • ", "  ▶ ", "  🟢 ") align
        // correctly — the previous unicodeScalars.count was wrong for any
        // bullet containing wide or multi-scalar grapheme clusters.
        let bulletWidth = VisibleWidth.measure(bullet)
        let indent      = String(repeating: " ", count: bulletWidth)
        let innerWidth  = max(10, width - bulletWidth)

        var isFirst = true
        for child in item.children {
            if isFirst, let para = child as? Paragraph {
                var prefix = bullet
                if let cb = item.checkbox {
                    prefix += (cb == .checked ? "☑ " : "☐ ")
                }
                let text    = inline(para)
                let wrapped = AnsiWrapping.wrap(text, width: innerWidth, breakOnWords: true)
                for (i, line) in wrapped.enumerated() {
                    output.append(i == 0 ? prefix + line : indent + line)
                }
                isFirst = false
            } else {
                // Nested list or other block content
                var innerLines = renderNestedBlock(child, innerWidth)
                while innerLines.last == "" { innerLines.removeLast() }
                for line in innerLines { output.append(indent + line) }
                isFirst = false
            }
        }
    }
}
