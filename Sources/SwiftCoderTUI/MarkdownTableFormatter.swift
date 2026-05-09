import Markdown

struct MarkdownTableFormatter {
    let palette: Palette
    let width: Int
    let inline: (any Markup) -> String

    func renderTable(_ table: Table) -> [String] {
        var headerCells: [String]   = []
        var bodyRows: [[String]]    = []

        for tableChild in table.children {
            if let head = tableChild as? Table.Head {
                for headChild in head.children {
                    if let row = headChild as? Table.Row {
                        for cell in row.children {
                            if let tableCell = cell as? Table.Cell {
                                headerCells.append(inline(tableCell))
                            }
                        }
                    }
                }
            } else if let body = tableChild as? Table.Body {
                for bodyChild in body.children {
                    if let row = bodyChild as? Table.Row {
                        var cells: [String] = []
                        for cell in row.children {
                            if let tableCell = cell as? Table.Cell {
                                cells.append(inline(tableCell))
                            }
                        }
                        bodyRows.append(cells)
                    }
                }
            }
        }

        guard !headerCells.isEmpty else { return [] }

        let colCount = headerCells.count

        // Cap each column width so a single oversized cell can't blow the
        // table past `width`. Each column needs 1 leading + 1 trailing space
        // plus a vertical border on the right; the leftmost vertical border
        // adds one more column. So column-content budget = width - 1 - 3*colCount.
        let chrome      = 1 + 3 * colCount
        let budget      = max(colCount, width - chrome)
        let maxColWidth = max(4, budget / colCount)

        // Natural width of every cell, then clamp to `maxColWidth`.
        var colWidths = headerCells.map { min(maxColWidth, VisibleWidth.measure($0)) }
        for rowCells in bodyRows {
            for (i, cell) in rowCells.prefix(colCount).enumerated() {
                let w = min(maxColWidth, VisibleWidth.measure(cell))
                if w > colWidths[i] { colWidths[i] = w }
            }
        }

        let box   = BoxStyle.single
        let bAttr = TextAttributes().foreground(palette.border)
        let hAttr = TextAttributes().bold()

        func makeSep(l: String, m: String, r: String) -> String {
            var s = l
            for (i, w) in colWidths.enumerated() {
                s += String(repeating: box.horizontal, count: w + 2)
                if i < colCount - 1 { s += m }
            }
            s += r
            return bAttr.apply(to: s)
        }

        // Wrap each cell to its column width and pad the row to the height of
        // the tallest cell, then emit one terminal line per wrapped row.
        // ANSI styles inside cells are preserved across breaks by AnsiWrapping.
        func makeRow(_ cells: [String], attr: TextAttributes = .plain) -> [String] {
            var wrapped: [[String]] = []
            wrapped.reserveCapacity(colCount)
            for i in 0..<colCount {
                let cell = i < cells.count ? cells[i] : ""
                let parts = cell.isEmpty
                    ? [""]
                    : AnsiWrapping.wrap(cell, width: colWidths[i], breakOnWords: true)
                wrapped.append(parts.isEmpty ? [""] : parts)
            }
            let height = wrapped.map(\.count).max() ?? 1

            var out: [String] = []
            out.reserveCapacity(height)
            let vbar = bAttr.apply(to: box.vertical)
            for row in 0..<height {
                var line = vbar
                for i in 0..<colCount {
                    let segment = row < wrapped[i].count ? wrapped[i][row] : ""
                    let vis     = VisibleWidth.measure(segment)
                    let pad     = String(repeating: " ", count: max(0, colWidths[i] - vis))
                    line += " " + attr.apply(to: segment + pad) + " " + vbar
                }
                out.append(line)
            }
            return out
        }

        var output: [String] = []
        output.append(makeSep(l: box.topLeft,    m: "┬", r: box.topRight))
        output.append(contentsOf: makeRow(headerCells, attr: hAttr))
        output.append(makeSep(l: box.teeLeft,    m: "┼", r: box.teeRight))
        for rowCells in bodyRows {
            output.append(contentsOf: makeRow(rowCells))
        }
        output.append(makeSep(l: box.bottomLeft, m: "┴", r: box.bottomRight))
        output.append("")
        return output
    }
}
