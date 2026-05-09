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
