import XCTest
@testable import SwiftCoderTUI

final class BoxStyleTests: XCTestCase {

    // MARK: - BoxStyle character sets

    func testSingleBoxCharacters() {
        let s = BoxStyle.single
        XCTAssertEqual(s.topLeft,     "┌")
        XCTAssertEqual(s.topRight,    "┐")
        XCTAssertEqual(s.bottomLeft,  "└")
        XCTAssertEqual(s.bottomRight, "┘")
        XCTAssertEqual(s.horizontal,  "─")
        XCTAssertEqual(s.vertical,    "│")
    }

    func testDoubleBoxCharacters() {
        let s = BoxStyle.double
        XCTAssertEqual(s.topLeft,    "╔")
        XCTAssertEqual(s.topRight,   "╗")
        XCTAssertEqual(s.horizontal, "═")
        XCTAssertEqual(s.vertical,   "║")
    }

    func testRoundedBoxCharacters() {
        let s = BoxStyle.rounded
        XCTAssertEqual(s.topLeft,    "╭")
        XCTAssertEqual(s.topRight,   "╮")
        XCTAssertEqual(s.bottomLeft, "╰")
        XCTAssertEqual(s.bottomRight,"╯")
    }

    func testAsciiBoxCharacters() {
        let s = BoxStyle.ascii
        XCTAssertEqual(s.topLeft,    "+")
        XCTAssertEqual(s.horizontal, "-")
        XCTAssertEqual(s.vertical,   "|")
    }

    // MARK: - BoxRenderer.draw(width:height:style:)

    func testDrawBoxDimensions() {
        let lines = BoxRenderer.draw(width: 5, height: 3, style: .single)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "┌───┐")
        XCTAssertEqual(lines[1], "│   │")
        XCTAssertEqual(lines[2], "└───┘")
    }

    func testDrawBoxAscii() {
        let lines = BoxRenderer.draw(width: 4, height: 2, style: .ascii)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "+--+")
        XCTAssertEqual(lines[1], "+--+")
    }

    func testDrawBoxTooSmallReturnsEmpty() {
        let lines = BoxRenderer.draw(width: 1, height: 1, style: .single)
        // width < 2 → empty strings, not a real box
        XCTAssertEqual(lines.count, 1)
    }

    // MARK: - BoxRenderer.draw(content:style:padding:)

    func testDrawBoxWithContent() {
        // content: ["Hi"], padding: 1
        // maxContentWidth = 2, innerWidth = 2 + 2*1 = 4
        // Lines: "+----+", "|    |", "| Hi |", "|    |", "+----+"
        let lines = BoxRenderer.draw(content: ["Hi"], style: .ascii, padding: 1)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0], "+----+")
        XCTAssertEqual(lines[1], "|    |")
        XCTAssertEqual(lines[2], "| Hi |")
        XCTAssertEqual(lines[3], "|    |")
        XCTAssertEqual(lines[4], "+----+")
    }

    func testDrawBoxWithZeroPadding() {
        // padding: 0 → no blank padding rows, content lines flush with border
        // innerWidth = 2 + 0 = 2
        // Lines: "+--+", "|Hi|", "+--+"
        let lines = BoxRenderer.draw(content: ["Hi"], style: .ascii, padding: 0)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "+--+")
        XCTAssertEqual(lines[1], "|Hi|")
        XCTAssertEqual(lines[2], "+--+")
    }

    func testDrawBoxContentWidthIsMaxOfLines() {
        let lines = BoxRenderer.draw(content: ["Hi", "Hello"], style: .ascii, padding: 0)
        // maxContentWidth = 5 ("Hello"), innerWidth = 5
        // "Hi" gets 3 trailing spaces
        XCTAssertEqual(lines[0], "+-----+")
        XCTAssertEqual(lines[1], "|Hi   |")
        XCTAssertEqual(lines[2], "|Hello|")
    }

    func testAllStylesProduceLinesOfEqualLength() {
        for style in BoxStyle.allCases {
            let lines = BoxRenderer.draw(width: 6, height: 4, style: style)
            XCTAssertEqual(lines.count, 4, "style \(style) should produce 4 lines")
            // All lines have the same visible width.
            let widths = lines.map { VisibleWidth.measure($0) }
            XCTAssertTrue(widths.allSatisfy { $0 == widths[0] },
                          "all lines for style \(style) should be same visible width")
        }
    }
}
