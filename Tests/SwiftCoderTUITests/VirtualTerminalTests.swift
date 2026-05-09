import XCTest
@testable import SwiftCoderTUI

final class VirtualTerminalTests: XCTestCase {

    func testWriteCaptures() {
        let t = VirtualTerminal()
        t.write("hello")
        XCTAssertEqual(t.output, "hello")
    }

    func testMultipleWritesAccumulate() {
        let t = VirtualTerminal()
        t.write("foo")
        t.write("bar")
        XCTAssertEqual(t.output, "foobar")
    }

    func testClearOutput() {
        let t = VirtualTerminal()
        t.write("hello")
        t.clearOutput()
        XCTAssertEqual(t.output, "")
    }

    func testClearThenWrite() {
        let t = VirtualTerminal()
        t.write("old")
        t.clearOutput()
        t.write("new")
        XCTAssertEqual(t.output, "new")
    }

    func testDefaultSize() {
        let t = VirtualTerminal()
        XCTAssertEqual(t.rows, 24)
        XCTAssertEqual(t.cols, 80)
    }

    func testCustomSize() {
        let t = VirtualTerminal(rows: 30, cols: 120)
        XCTAssertEqual(t.rows, 30)
        XCTAssertEqual(t.cols, 120)
    }

    func testFrameBufferingHoldsOutput() {
        let t = VirtualTerminal()
        t.beginFrame()
        t.write("buffered")
        XCTAssertEqual(t.output, "", "output should be empty until endFrame")
    }

    func testFrameBufferingFlushesOnEnd() {
        let t = VirtualTerminal()
        t.beginFrame()
        t.write("buffered")
        t.endFrame()
        XCTAssertEqual(t.output, "buffered")
    }

    func testFrameBufferingMultipleWrites() {
        let t = VirtualTerminal()
        t.beginFrame()
        t.write("A")
        t.write("B")
        t.write("C")
        t.endFrame()
        XCTAssertEqual(t.output, "ABC")
    }

    func testMoveToEmitsAnsi() {
        let t = VirtualTerminal()
        t.moveTo(row: 3, col: 5)
        XCTAssertEqual(t.output, "\u{1B}[3;5H")
    }

    func testClearLineEmitsAnsi() {
        let t = VirtualTerminal()
        t.clearLine()
        XCTAssertTrue(t.output.contains("\u{1B}[2K"))
    }

    func testHideCursorEmitsAnsi() {
        let t = VirtualTerminal()
        t.hideCursor()
        XCTAssertEqual(t.output, "\u{1B}[?25l")
    }

    func testShowCursorEmitsAnsi() {
        let t = VirtualTerminal()
        t.showCursor()
        XCTAssertEqual(t.output, "\u{1B}[?25h")
    }

    func testLifecycleMethodsAreNoOps() {
        let t = VirtualTerminal()
        t.setupRawMode(title: "Test")
        t.restoreMode()
        t.setTitle("Title")
        t.updateSize()
        t.setBracketedPaste(enabled: true)
        t.setBracketedPaste(enabled: false)
        XCTAssertEqual(t.output, "")
    }
}
