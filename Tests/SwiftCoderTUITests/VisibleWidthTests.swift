import XCTest
@testable import SwiftCoderTUI

final class VisibleWidthTests: XCTestCase {

    // MARK: - measure

    func testMeasurePlainText() {
        XCTAssertEqual(VisibleWidth.measure("hello"), 5)
    }

    func testMeasureEmpty() {
        XCTAssertEqual(VisibleWidth.measure(""), 0)
    }

    func testMeasureWithAnsiCSI() {
        XCTAssertEqual(VisibleWidth.measure("\u{1B}[31mhello\u{1B}[0m"), 5)
    }

    func testMeasureWideChars() {
        // 你 and 好 are each 2 columns wide → total 4
        XCTAssertEqual(VisibleWidth.measure("你好"), 4)
    }

    func testMeasureMixedAsciiAndWide() {
        // "A" (1) + "你" (2) = 3
        XCTAssertEqual(VisibleWidth.measure("A你"), 3)
    }

    /// Regression test: ✅/❌ (Dingbats, U+2700–U+27BF) and ⚠️ (Misc Symbols,
    /// U+2600–U+26FF) are rendered emoji-width-2 by every terminal this app
    /// targets, but were missing from `charWidth`'s wide-character ranges —
    /// undercounting them as width 1 desyncs the renderer's row-count
    /// bookkeeping (`renderedFooterLineCount` / `renderedCursorFooterRow`)
    /// from the terminal's real cursor position by one row per occurrence.
    /// Compounds badly across a run with many tool-result lines (every
    /// result is prefixed with ✅ or ❌), e.g. a sub-agent chaining several
    /// tool calls — the footer/spinner drifts further off with each one.
    func testMeasureDingbatsAndMiscSymbolsEmojiAreWide() {
        XCTAssertEqual(VisibleWidth.measure("✅"), 2, "check mark (U+2705)")
        XCTAssertEqual(VisibleWidth.measure("❌"), 2, "cross mark (U+274C)")
        XCTAssertEqual(VisibleWidth.measure("⚠️"), 2, "warning sign (U+26A0, base scalar)")
    }

    func testMeasureToolResultLinePrefixWidth() {
        // Exactly the shape SessionModel/StreamRenderer prefix tool results
        // with: "✅ " / "❌ " followed by text.
        XCTAssertEqual(VisibleWidth.measure("✅ done"), 7) // 2 + 1 + "done"(4)
        XCTAssertEqual(VisibleWidth.measure("❌ failed"), 9) // 2 + 1 + "failed"(6)
    }

    // MARK: - stripAnsi

    func testStripAnsiCSISequence() {
        XCTAssertEqual(VisibleWidth.stripAnsi("\u{1B}[31mred\u{1B}[0m"), "red")
    }

    func testStripAnsiOSCSequence() {
        // OSC 8 hyperlink: ESC ] 8 ; ; url ESC \ text ESC ] 8 ; ; ESC \
        let s = "\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\"
        XCTAssertEqual(VisibleWidth.stripAnsi(s), "link")
    }

    func testStripAnsiPreservesPlainText() {
        XCTAssertEqual(VisibleWidth.stripAnsi("plain"), "plain")
    }

    func testStripAnsiMultipleSequences() {
        let s = "\u{1B}[1m\u{1B}[32mGreen Bold\u{1B}[0m"
        XCTAssertEqual(VisibleWidth.stripAnsi(s), "Green Bold")
    }

    // MARK: - truncate

    func testTruncateNoOpWhenShort() {
        XCTAssertEqual(VisibleWidth.truncate("hello", maxWidth: 5), "hello")
    }

    func testTruncateNoOpWhenExact() {
        XCTAssertEqual(VisibleWidth.truncate("hello", maxWidth: 10), "hello")
    }

    func testTruncateWithoutEllipsisWhenNoRoom() {
        // "hello world" at maxWidth 5: emits "hello" (5 cols), next char ' ' would
        // make it 6 > 5.  visibleWidth(5) + ellipsisWidth(1) = 6 > 5 → no ellipsis.
        let result = VisibleWidth.truncate("hello world", maxWidth: 5)
        XCTAssertEqual(result, "hello")
        XCTAssertFalse(result.contains("…"))
    }

    func testTruncateAddsEllipsisForWideChars() {
        // "你好啊": 你(2)+好(2)+啊(2)=6 cols
        // maxWidth 5: 你(2)+好(2)=4 emitted, 啊(2) would make 6>5 → truncated.
        // visibleWidth(4) + ellipsisWidth(1) = 5 <= 5 → ellipsis added.
        let result = VisibleWidth.truncate("你好啊", maxWidth: 5)
        XCTAssertTrue(result.hasPrefix("你好"))
        XCTAssertTrue(result.contains("…"))
    }

    func testTruncatePreservesAnsiSequences() {
        // Styled text: ANSI wraps "hello world".
        // truncate should pass through ANSI verbatim.
        let styled = "\u{1B}[31mhello world\u{1B}[0m"
        let result = VisibleWidth.truncate(styled, maxWidth: 5)
        XCTAssertTrue(result.contains("\u{1B}[31m"))
        XCTAssertTrue(result.contains("hello"))
    }
}
