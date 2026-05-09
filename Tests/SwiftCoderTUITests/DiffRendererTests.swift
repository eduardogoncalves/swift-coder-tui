import XCTest
@testable import SwiftCoderTUI

final class DiffRendererTests: XCTestCase {

    // MARK: - Full render (previous == nil)

    func testFullRenderStartsWithClearScreen() {
        let buf = FrameBuffer(width: 3, height: 1)
        let result = DiffRenderer.render(previous: nil, current: buf)
        XCTAssertTrue(result.hasPrefix("\u{1B}[2J"),
                      "full render should clear the screen first")
    }

    func testFullRenderContainsWrittenText() {
        var buf = FrameBuffer(width: 5, height: 1)
        buf.writeText("AB", x: 0, y: 0)
        let result = DiffRenderer.render(previous: nil, current: buf)
        XCTAssertTrue(result.contains("AB"))
    }

    func testFullRenderEndsWithReset() {
        let buf = FrameBuffer(width: 3, height: 1)
        XCTAssertTrue(DiffRenderer.render(previous: nil, current: buf).hasSuffix("\u{1B}[0m"))
    }

    // MARK: - Diff render (identical buffers)

    func testIdenticalBuffersProduceMinimalOutput() {
        let buf = FrameBuffer(width: 3, height: 1)
        let result = DiffRenderer.render(previous: buf, current: buf)
        // No cells changed → no cursor moves, no characters — only the trailing reset.
        XCTAssertEqual(result, "\u{1B}[0m")
    }

    func testIdenticalNonEmptyBuffersProduceMinimalOutput() {
        var buf = FrameBuffer(width: 5, height: 1)
        buf.writeText("Hello", x: 0, y: 0)
        let result = DiffRenderer.render(previous: buf, current: buf)
        XCTAssertEqual(result, "\u{1B}[0m")
    }

    // MARK: - Diff render (single cell change)

    func testSingleCellChangeCursorPositionedCorrectly() {
        let prev = FrameBuffer(width: 3, height: 1)
        var curr = FrameBuffer(width: 3, height: 1)
        curr[1, 0] = Cell(character: "X")
        let result = DiffRenderer.render(previous: prev, current: curr)
        // ANSI cursor: row=1, col=2 (1-based).
        XCTAssertTrue(result.contains("\u{1B}[1;2H"), "cursor should be at row 1, col 2")
        XCTAssertTrue(result.contains("X"))
        XCTAssertTrue(result.hasSuffix("\u{1B}[0m"))
    }

    func testSingleCellChangeAtOrigin() {
        let prev = FrameBuffer(width: 3, height: 1)
        var curr = FrameBuffer(width: 3, height: 1)
        curr[0, 0] = Cell(character: "Z")
        let result = DiffRenderer.render(previous: prev, current: curr)
        XCTAssertTrue(result.contains("\u{1B}[1;1H"))
        XCTAssertTrue(result.contains("Z"))
    }

    func testOnlyChangedCellsAreEmitted() {
        var prev = FrameBuffer(width: 3, height: 1)
        prev.writeText("AAA", x: 0, y: 0)
        var curr = FrameBuffer(width: 3, height: 1)
        curr.writeText("ABA", x: 0, y: 0)
        let result = DiffRenderer.render(previous: prev, current: curr)
        // Only col 1 changed → cursor to (1,2), emit "B".
        XCTAssertTrue(result.contains("\u{1B}[1;2H"))
        XCTAssertFalse(result.contains("\u{1B}[1;1H"), "unchanged cells should not reposition cursor")
    }

    // MARK: - Dimension mismatch triggers full render

    func testMismatchedDimensionsFallsBackToFullRender() {
        let small = FrameBuffer(width: 3, height: 1)
        let large = FrameBuffer(width: 5, height: 2)
        let result = DiffRenderer.render(previous: small, current: large)
        // Should behave like a full render.
        XCTAssertTrue(result.hasPrefix("\u{1B}[2J"))
    }

    // MARK: - SGR transitions in diff render

    func testDiffRenderEmitsSGRForStyledCell() {
        let prev = FrameBuffer(width: 3, height: 1)
        var curr = FrameBuffer(width: 3, height: 1)
        curr[0, 0] = Cell(character: "R", foreground: .rgb(255, 0, 0))
        let result = DiffRenderer.render(previous: prev, current: curr)
        XCTAssertTrue(result.contains("38;2;255;0;0"), "diff should emit foreground SGR")
        XCTAssertTrue(result.contains("R"))
    }
}
