import XCTest
@testable import SwiftCoderTUI

/// Verifies that the footer's top separator does NOT appear as a ghost line
/// in the scroll area after a stats line is printed while the spinner is visible.
final class RendererSeparatorTests: XCTestCase {

    // MARK: - Helpers

    private static let testConfig = AppConfig(
        appName: "Test",
        version: "0.0.1",
        welcomeMessage: "testing",
        models: [AppConfig.ModelConfig(id: "m", label: "M")],
        modes: [AppConfig.ModeConfig(id: "normal", label: "NORMAL",
                                     barColor: "", badgeColor: "")],
        commands: []
    )

    /// Strip all ANSI escape sequences and return plain text.
    private func stripAnsi(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{001B}" {
                i = s.index(after: i)
                guard i < s.endIndex && s[i] == "[" else { continue }
                i = s.index(after: i)
                while i < s.endIndex && !s[i].isLetter {
                    i = s.index(after: i)
                }
                if i < s.endIndex { i = s.index(after: i) }
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }

    /// Parse the ANSI output into a simulated screen.
    /// Returns an array of rows (0-indexed). Handles: CR/LF, ESC[nA (cursor up),
    /// ESC[K/2K (erase line), ESC[0J (erase to end of screen),
    /// ESC[r;cH (move cursor), ESC[nG (column set), CSI mode sequences (ignored).
    ///
    /// Iterates over Unicode scalars (not Characters) to avoid treating the
    /// `\r\n` pair as a single grapheme cluster.
    private func renderToScreen(_ output: String, rows: Int, cols: Int) -> [[Character]] {
        var screen = Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        var curRow = 0
        var curCol = 0

        let scalars = Array(output.unicodeScalars)
        var i = 0

        func writeScalar(_ sv: Unicode.Scalar) {
            guard curRow >= 0, curRow < rows, curCol >= 0, curCol < cols else { return }
            screen[curRow][curCol] = Character(sv)
            curCol += 1
        }

        // Returns true if a scalar value is a CSI final byte (0x40–0x7E).
        func isFinalByte(_ v: UInt32) -> Bool { v >= 0x40 && v <= 0x7E }

        while i < scalars.count {
            let sv = scalars[i]

            if sv.value == 0x1B {  // ESC
                guard i + 1 < scalars.count else { break }
                if scalars[i + 1].value == 0x5B {  // [  → CSI sequence
                    var params = ""
                    var j = i + 2
                    while j < scalars.count && !isFinalByte(scalars[j].value) {
                        params.append(Character(scalars[j]))
                        j += 1
                    }
                    let cmd = j < scalars.count ? Character(scalars[j]) : "?"
                    i = j < scalars.count ? j + 1 : j

                    switch cmd {
                    case "A":  // cursor up
                        let n = Int(params) ?? 1
                        curRow = max(0, curRow - n)
                    case "G":  // set column (1-indexed)
                        let n = (Int(params) ?? 1) - 1
                        curCol = max(0, min(cols - 1, n))
                    case "H":  // move to row;col (1-indexed)
                        let parts = params.split(separator: ";").compactMap { Int($0) }
                        curRow = max(0, min(rows - 1, (parts.count > 0 ? parts[0] : 1) - 1))
                        curCol = max(0, min(cols - 1, (parts.count > 1 ? parts[1] : 1) - 1))
                    case "J":  // erase
                        if params == "0" || params == "" {
                            for c in curCol..<cols { screen[curRow][c] = " " }
                            for r in (curRow + 1)..<rows { for c in 0..<cols { screen[r][c] = " " } }
                        } else if params == "2" {
                            for r in 0..<rows { for c in 0..<cols { screen[r][c] = " " } }
                        }
                    case "K":  // erase in line
                        if params == "2" {
                            for c in 0..<cols { screen[curRow][c] = " " }
                        } else {
                            for c in curCol..<cols { screen[curRow][c] = " " }
                        }
                    default: break
                    }
                } else if scalars[i + 1].value == 0x5D {  // ]  → OSC sequence
                    var j = i + 2
                    while j < scalars.count && scalars[j].value != 0x07 { j += 1 }  // skip to BEL
                    i = j < scalars.count ? j + 1 : j
                } else {
                    i += 1
                }
                continue
            }

            switch sv.value {
            case 0x0D:  // CR
                curCol = 0
            case 0x0A:  // LF
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

    /// Convert a screen row to a trimmed plain string.
    private func rowText(_ screen: [[Character]], _ row: Int) -> String {
        String(screen[row]).replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Tests

    /// Key scenario: print a stats line while the spinner is active, then end
    /// generation.  The top separator must NOT appear as a ghost above the footer.
    func testNoGhostSeparatorAfterStatsWhileGenerating() async {
        let term = VirtualTerminal(rows: 10, cols: 40)
        let renderer = Renderer(config: Self.testConfig, terminal: term)
        await renderer.setupScreen()
        await renderer.setGenerating(true)
        await renderer.renderFooter()

        // Simulate: stats line printed while spinner visible
        await renderer.printScrollLine("Generated 500 tokens")

        // Simulate: generation ended
        await renderer.setGenerating(false)
        await renderer.renderFooter()

        let output = term.output
        let screen = renderToScreen(output, rows: 10, cols: 40)

        // Find the rows containing the separator (─────)
        let separatorPattern = "─"
        var separatorRows: [Int] = []
        for r in 0..<10 {
            let text = String(screen[r])
            if text.contains(separatorPattern) {
                separatorRows.append(r)
            }
        }

        // There should be exactly 2 separator rows (top and bottom of footer),
        // and they must be adjacent (top-sep immediately above input, bot-sep below).
        XCTAssertEqual(separatorRows.count, 2,
            "Expected exactly 2 separator lines, got \(separatorRows.count): rows \(separatorRows)\nScreen:\n\(dumpScreen(screen))")

        // The two separators must be adjacent (no gap between them)
        if separatorRows.count == 2 {
            XCTAssertEqual(separatorRows[1] - separatorRows[0], 2,
                "Separators should be 2 rows apart (with input between), but rows are \(separatorRows)\nScreen:\n\(dumpScreen(screen))")
        }
    }

    /// Verify that the stats line itself appears above the footer separator.
    func testStatsLineAppearsAboveFooter() async {
        let term = VirtualTerminal(rows: 10, cols: 40)
        let renderer = Renderer(config: Self.testConfig, terminal: term)
        await renderer.setupScreen()
        await renderer.setGenerating(true)
        await renderer.renderFooter()

        await renderer.printScrollLine("Generated 500 tokens")
        await renderer.setGenerating(false)
        await renderer.renderFooter()

        let screen = renderToScreen(term.output, rows: 10, cols: 40)

        // Find stats and first separator rows
        var statsRow = -1
        var firstSepRow = -1
        for r in 0..<10 {
            let text = String(screen[r])
            if text.contains("Generated") { statsRow = r }
            if text.contains("─") && firstSepRow == -1 { firstSepRow = r }
        }

        XCTAssertGreaterThanOrEqual(statsRow, 0, "Stats line not found on screen\nScreen:\n\(dumpScreen(screen))")
        XCTAssertGreaterThan(firstSepRow, statsRow,
            "Footer separator should be BELOW stats line, but stats=\(statsRow) sep=\(firstSepRow)\nScreen:\n\(dumpScreen(screen))")
    }

    /// Debug helper: dump raw ANSI output to see what the renderer actually produces.
    func testDumpRawOutput() async {
        let term = VirtualTerminal(rows: 10, cols: 40)
        let renderer = Renderer(config: Self.testConfig, terminal: term)
        await renderer.setupScreen()
        await renderer.setGenerating(true)
        await renderer.renderFooter()
        await renderer.printScrollLine("Generated 500 tokens")
        await renderer.setGenerating(false)
        await renderer.renderFooter()

        let raw = term.output
        var escaped = ""
        for ch in raw.unicodeScalars {
            switch ch.value {
            case 0x1B: escaped += "<ESC>"
            case 0x0D: escaped += "<CR>"
            case 0x0A: escaped += "<LF>"
            case 0x07: escaped += "<BEL>"
            default:   escaped += String(ch)
            }
        }
        // Just print it; this test always passes, used for debugging
        print("RAW OUTPUT:\n\(escaped)")
        XCTAssertTrue(true)
    }

    private func dumpScreen(_ screen: [[Character]]) -> String {
        screen.enumerated().map { (i, row) in
            "\(i): \(String(row))"
        }.joined(separator: "\n")
    }
}
