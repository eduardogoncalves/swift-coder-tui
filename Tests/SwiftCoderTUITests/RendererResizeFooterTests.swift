import XCTest
@testable import SwiftCoderTUI

final class RendererResizeFooterTests: XCTestCase {
    private static let config = AppConfig(
        appName: "Test",
        version: "0.0.1",
        welcomeMessage: "testing",
        models: [AppConfig.ModelConfig(id: "model", label: "Model-X")],
        modes: [AppConfig.ModeConfig(id: "fast", label: "FAST", barColor: "", badgeColor: "")],
        commands: []
    )

    private final class ResizableTerminal: Terminal, @unchecked Sendable {
        private(set) var rows: Int
        private(set) var cols: Int
        private var pendingSize: (rows: Int, cols: Int)?
        private var buffer = ""
        private var frameBuffer = ""
        private var inFrame = false

        var output: String { buffer }

        init(rows: Int, cols: Int) {
            self.rows = rows
            self.cols = cols
        }

        func queueResize(rows: Int, cols: Int) {
            pendingSize = (rows, cols)
        }

        func clearOutput() {
            buffer = ""
        }

        func write(_ s: String) {
            if inFrame { frameBuffer.append(s) } else { buffer.append(s) }
        }

        func moveTo(row: Int, col: Int) { write(EscapeSequence.moveTo(row: row, col: col)) }
        func clearLine() { write(EscapeSequence.clearLine()) }
        func clearToEndOfLine() { write("\u{001B}[K") }
        func clearScreen() { write("\u{001B}[2J") }
        func hideCursor() { write(EscapeSequence.hideCursor()) }
        func showCursor() { write(EscapeSequence.showCursor()) }
        func setupRawMode(title: String) {}
        func restoreMode() {}
        func setTitle(_ title: String) {}
        func setBracketedPaste(enabled: Bool) {}

        func updateSize() {
            guard let size = pendingSize else { return }
            rows = size.rows
            cols = size.cols
            pendingSize = nil
        }

        func beginFrame() {
            inFrame = true
            frameBuffer.removeAll(keepingCapacity: true)
        }

        func endFrame() {
            inFrame = false
            buffer.append(frameBuffer)
            frameBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func renderToScreen(_ output: String, rows: Int, cols: Int) -> [[Character]] {
        var screen = Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        var curRow = 0
        var curCol = 0
        let scalars = Array(output.unicodeScalars)
        var i = 0

        func isFinalByte(_ v: UInt32) -> Bool { v >= 0x40 && v <= 0x7E }
        func writeScalar(_ sv: Unicode.Scalar) {
            guard curRow >= 0, curRow < rows, curCol >= 0, curCol < cols else { return }
            screen[curRow][curCol] = Character(sv)
            curCol += 1
        }

        while i < scalars.count {
            let sv = scalars[i]
            if sv.value == 0x1B {
                guard i + 1 < scalars.count else { break }
                if scalars[i + 1].value == 0x5B {
                    var params = ""
                    var j = i + 2
                    while j < scalars.count && !isFinalByte(scalars[j].value) {
                        params.append(Character(scalars[j]))
                        j += 1
                    }
                    let cmd = j < scalars.count ? Character(scalars[j]) : "?"
                    i = j < scalars.count ? j + 1 : j

                    switch cmd {
                    case "A":
                        let n = Int(params) ?? 1
                        curRow = max(0, curRow - n)
                    case "B":
                        let n = Int(params) ?? 1
                        curRow = min(rows - 1, curRow + n)
                    case "G":
                        let n = (Int(params) ?? 1) - 1
                        curCol = max(0, min(cols - 1, n))
                    case "H":
                        let parts = params.split(separator: ";").compactMap { Int($0) }
                        curRow = max(0, min(rows - 1, (parts.count > 0 ? parts[0] : 1) - 1))
                        curCol = max(0, min(cols - 1, (parts.count > 1 ? parts[1] : 1) - 1))
                    case "J":
                        if params == "0" || params == "" {
                            for c in curCol..<cols { screen[curRow][c] = " " }
                            if curRow + 1 < rows {
                                for r in (curRow + 1)..<rows { for c in 0..<cols { screen[r][c] = " " } }
                            }
                        } else if params == "2" {
                            for r in 0..<rows { for c in 0..<cols { screen[r][c] = " " } }
                        }
                    case "K":
                        if params == "2" {
                            for c in 0..<cols { screen[curRow][c] = " " }
                        } else {
                            for c in curCol..<cols { screen[curRow][c] = " " }
                        }
                    default:
                        break
                    }
                    continue
                } else if scalars[i + 1].value == 0x5D {
                    var j = i + 2
                    while j < scalars.count && scalars[j].value != 0x07 { j += 1 }
                    i = j < scalars.count ? j + 1 : j
                    continue
                }
            }

            switch sv.value {
            case 0x0D:
                curCol = 0
            case 0x0A:
                if curRow + 1 < rows {
                    curRow += 1
                } else {
                    for r in 0..<rows - 1 { screen[r] = screen[r + 1] }
                    screen[rows - 1] = Array(repeating: " ", count: cols)
                }
            default:
                writeScalar(sv)
            }
            i += 1
        }

        return screen
    }

    private func assertSingleFooter(
        _ screen: [[Character]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var separatorRows: [Int] = []
        var statusRows: [Int] = []
        var inputRows: [Int] = []

        for row in 0..<screen.count {
            let text = String(screen[row])
            if text.contains("─") { separatorRows.append(row) }
            if text.contains("/ commands") { statusRows.append(row) }
            if text.contains("> ") { inputRows.append(row) }
        }

        XCTAssertEqual(separatorRows.count, 2, "Expected 2 separators, got \(separatorRows)", file: file, line: line)
        if separatorRows.count == 2 {
            XCTAssertEqual(separatorRows[1] - separatorRows[0], 2, "Separators should frame one input row", file: file, line: line)
        }
        XCTAssertEqual(statusRows.count, 1, "Expected exactly one status row, got \(statusRows)", file: file, line: line)
        XCTAssertEqual(inputRows.count, 1, "Expected exactly one input row, got \(inputRows)", file: file, line: line)
    }

    func testShrinkResizeDoesNotDuplicateFooterRows() async {
        let term = ResizableTerminal(rows: 40, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: term)
        await renderer.setupScreen()
        await renderer.renderFooter()
        for i in 0..<20 {
            await renderer.printScrollLine("line \(i)")
        }

        term.queueResize(rows: 12, cols: 60)
        let old = await renderer.updateSize()
        await renderer.handleResize(oldRows: old.oldRows, oldCols: old.oldCols)
        await renderer.renderFooter()

        let screen = renderToScreen(term.output, rows: 12, cols: 60)
        assertSingleFooter(screen)

        let rendered = screen.map { String($0) }.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("[Model-X](FAST)"), rendered)
    }

    func testRepeatedResizeSignalsAfterShrinkStayStable() async {
        let term = ResizableTerminal(rows: 40, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: term)
        await renderer.setupScreen()
        await renderer.renderFooter()
        await renderer.setInputBuffer("status check")

        term.queueResize(rows: 14, cols: 70)
        let old = await renderer.updateSize()
        await renderer.handleResize(oldRows: old.oldRows, oldCols: old.oldCols)
        term.clearOutput()

        for _ in 0..<4 {
            await renderer.handleResize(oldRows: 14, oldCols: 70)
        }
        await renderer.renderFooter()

        let screen = renderToScreen(term.output, rows: 14, cols: 70)
        assertSingleFooter(screen)
    }

    func testLargeToSmallResizeKeepsSingleFooter() async {
        let term = ResizableTerminal(rows: 36, cols: 220)
        let renderer = Renderer(config: Self.config, terminal: term)
        await renderer.setupScreen()
        for i in 0..<12 {
            await renderer.printScrollLine("line \(i)")
        }

        term.queueResize(rows: 14, cols: 60)
        let old = await renderer.updateSize()
        await renderer.handleResize(oldRows: old.oldRows, oldCols: old.oldCols)
        let screen = renderToScreen(term.output, rows: 14, cols: 60)
        assertSingleFooter(screen)
    }
}
