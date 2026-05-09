import XCTest
@testable import SwiftCoderTUI

final class FrameBufferTests: XCTestCase {

    // MARK: - Init / subscript

    func testInitFillsWithEmpty() {
        let fb = FrameBuffer(width: 3, height: 2)
        XCTAssertEqual(fb[0, 0], Cell.empty)
        XCTAssertEqual(fb[2, 1], Cell.empty)
    }

    func testOutOfBoundsReadReturnsEmpty() {
        let fb = FrameBuffer(width: 3, height: 2)
        XCTAssertEqual(fb[5, 5], Cell.empty)
        XCTAssertEqual(fb[-1, 0], Cell.empty)
    }

    // MARK: - writeText

    func testWriteTextPlacesCharacters() {
        var fb = FrameBuffer(width: 5, height: 1)
        fb.writeText("AB", x: 0, y: 0)
        XCTAssertEqual(fb[0, 0].character, "A")
        XCTAssertEqual(fb[1, 0].character, "B")
        // Remaining cells untouched.
        XCTAssertEqual(fb[2, 0], Cell.empty)
    }

    func testWriteTextSetsAttributes() {
        var fb = FrameBuffer(width: 5, height: 1)
        let attrs = TextAttributes().bold()
        fb.writeText("X", x: 0, y: 0, attributes: attrs)
        XCTAssertTrue(fb[0, 0].bold)
    }

    func testWriteTextClipsAtRightEdge() {
        var fb = FrameBuffer(width: 3, height: 1)
        fb.writeText("ABCDE", x: 0, y: 0)
        XCTAssertEqual(fb[0, 0].character, "A")
        XCTAssertEqual(fb[1, 0].character, "B")
        XCTAssertEqual(fb[2, 0].character, "C")
    }

    func testWriteTextOffScreenRowIsNoOp() {
        var fb = FrameBuffer(width: 3, height: 1)
        fb.writeText("Hi", x: 0, y: 5)
        XCTAssertEqual(fb[0, 0], Cell.empty)
    }

    func testWriteTextStripsAnsi() {
        var fb = FrameBuffer(width: 5, height: 1)
        fb.writeText("\u{1B}[31mHi\u{1B}[0m", x: 0, y: 0)
        // ANSI stripped; 'H' and 'i' placed at x=0,1.
        XCTAssertEqual(fb[0, 0].character, "H")
        XCTAssertEqual(fb[1, 0].character, "i")
    }

    func testWriteTextWideCharOccupiesTwoColumns() {
        var fb = FrameBuffer(width: 5, height: 1)
        fb.writeText("你", x: 0, y: 0)
        XCTAssertTrue(fb[0, 0].isWide)
        XCTAssertTrue(fb[1, 0].isContinuation)
    }

    // MARK: - fill

    func testFillRect() {
        var fb = FrameBuffer(width: 5, height: 3)
        let red = Cell(character: "X", foreground: .rgb(255, 0, 0))
        fb.fill(rect: (x: 1, y: 1, w: 2, h: 1), cell: red)
        XCTAssertEqual(fb[1, 1], red)
        XCTAssertEqual(fb[2, 1], red)
        XCTAssertEqual(fb[0, 1], Cell.empty)
        XCTAssertEqual(fb[1, 0], Cell.empty)
    }

    // MARK: - overlay

    func testOverlayComposites() {
        var base = FrameBuffer(width: 5, height: 1)
        base.writeText("XXXXX", x: 0, y: 0)

        var overlay = FrameBuffer(width: 2, height: 1)
        overlay.writeText("AB", x: 0, y: 0)

        base.overlay(overlay, at: 1, y: 0)

        XCTAssertEqual(base[0, 0].character, "X")
        XCTAssertEqual(base[1, 0].character, "A")
        XCTAssertEqual(base[2, 0].character, "B")
        XCTAssertEqual(base[3, 0].character, "X")
    }

    func testOverlayWithTransparentSkipsMatchingCells() {
        var base = FrameBuffer(width: 3, height: 1)
        base.writeText("ABC", x: 0, y: 0)

        var overlay = FrameBuffer(width: 3, height: 1)
        overlay.writeText("X", x: 1, y: 0)    // only x=1 is non-empty

        base.overlay(overlay, at: 0, y: 0, transparent: Cell.empty)

        // x=0 and x=2: transparent in overlay → base chars preserved.
        XCTAssertEqual(base[0, 0].character, "A")
        XCTAssertEqual(base[1, 0].character, "X")
        XCTAssertEqual(base[2, 0].character, "C")
    }

    // MARK: - render

    func testRenderStartsWithResetAndHome() {
        let fb = FrameBuffer(width: 3, height: 1)
        let output = fb.render()
        XCTAssertTrue(output.hasPrefix("\u{1B}[0m\u{1B}[H"),
                      "render output should begin with reset+home")
    }

    func testRenderEndsWithReset() {
        let fb = FrameBuffer(width: 3, height: 1)
        XCTAssertTrue(fb.render().hasSuffix("\u{1B}[0m"))
    }

    func testRenderContainsWrittenText() {
        var fb = FrameBuffer(width: 5, height: 1)
        fb.writeText("Hi!", x: 0, y: 0)
        XCTAssertTrue(fb.render().contains("Hi!"))
    }

    func testRenderExactOutputForSimpleBuffer() {
        // 3-wide, 1-tall buffer with "Hi!" — no SGR transitions needed (no styling).
        var fb = FrameBuffer(width: 3, height: 1)
        fb.writeText("Hi!", x: 0, y: 0)
        // Expected: reset, home, "Hi!", final reset
        let expected = "\u{1B}[0m\u{1B}[HHi!\u{1B}[0m"
        XCTAssertEqual(fb.render(), expected)
    }

    func testRenderMultipleRows() {
        var fb = FrameBuffer(width: 3, height: 2)
        fb.writeText("ABC", x: 0, y: 0)
        fb.writeText("DEF", x: 0, y: 1)
        let output = fb.render()
        XCTAssertTrue(output.contains("ABC"))
        XCTAssertTrue(output.contains("DEF"))
        // Row 1 (second row) is positioned with ESC[2;1H.
        XCTAssertTrue(output.contains("\u{1B}[2;1H"))
    }

    func testRenderStyledCellEmitsSGR() {
        var fb = FrameBuffer(width: 1, height: 1)
        fb[0, 0] = Cell(character: "X", foreground: .rgb(255, 0, 0))
        let output = fb.render()
        // The foreground RGB SGR should appear in the output.
        XCTAssertTrue(output.contains("38;2;255;0;0"))
    }
}
