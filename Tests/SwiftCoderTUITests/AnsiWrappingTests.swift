import XCTest
@testable import SwiftCoderTUI

final class AnsiWrappingTests: XCTestCase {

    // MARK: - Empty input

    func testWrapEmptyInput() {
        XCTAssertEqual(AnsiWrapping.wrap("", width: 10), [])
    }

    func testWrapEmptyInputWordWrap() {
        XCTAssertEqual(AnsiWrapping.wrap("", width: 10, breakOnWords: true), [])
    }

    // MARK: - Hard wrap (plain text)

    func testHardWrapExactFit() {
        let lines = AnsiWrapping.wrap("abc", width: 3)
        XCTAssertEqual(lines, ["abc"])
    }

    func testHardWrapSplitsCleanly() {
        // "abcdef" → ["abc", "def"] at width 3
        let lines = AnsiWrapping.wrap("abcdef", width: 3)
        XCTAssertEqual(lines, ["abc", "def"])
    }

    func testHardWrapThreeSegments() {
        let lines = AnsiWrapping.wrap("abcdefghi", width: 3)
        XCTAssertEqual(lines, ["abc", "def", "ghi"])
    }

    // MARK: - Word wrap

    func testWordWrapBreaksOnSpace() {
        // "foo bar baz" at width 7: "foo bar" (7) then "baz"
        let lines = AnsiWrapping.wrap("foo bar baz", width: 7, breakOnWords: true)
        XCTAssertEqual(lines, ["foo bar", "baz"])
    }

    func testWordWrapSingleWord() {
        let lines = AnsiWrapping.wrap("hello", width: 10, breakOnWords: true)
        XCTAssertEqual(lines, ["hello"])
    }

    func testWordWrapFallsBackToHardBreak() {
        // A single word longer than width is hard-broken.
        let lines = AnsiWrapping.wrap("abcdefghi", width: 3, breakOnWords: true)
        XCTAssertEqual(lines, ["abc", "def", "ghi"])
    }

    // MARK: - SGR style preservation

    func testStyledTextWrapsPreservingOpenStyle() {
        // "\u{1B}[1mhello\u{1B}[0m" hard-wrapped at 3:
        // Line 1: "\u{1B}[1mhel\u{1B}[0m"  (bold opened, hard-break closes it)
        // Line 2: "\u{1B}[1mlo\u{1B}[0m"   (bold re-opened on continuation)
        let lines = AnsiWrapping.wrap("\u{1B}[1mhello\u{1B}[0m", width: 3)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("\u{1B}[1m"), "first line should open bold")
        XCTAssertTrue(lines[0].contains("\u{1B}[0m"), "first line should close bold on break")
        XCTAssertTrue(lines[1].contains("\u{1B}[1m"), "continuation line should re-open bold")
    }

    func testStyleClosedAtLineBreak() {
        let lines = AnsiWrapping.wrap("\u{1B}[1mhello\u{1B}[0m", width: 3)
        // After the hard break the first line must end with a reset.
        XCTAssertTrue(lines[0].hasSuffix("\u{1B}[0m"))
    }

    // MARK: - Newline handling

    func testExplicitNewlineCreatesNewLine() {
        let lines = AnsiWrapping.wrap("a\nb", width: 10)
        XCTAssertEqual(lines, ["a", "b"])
    }
}
