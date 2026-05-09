import XCTest
@testable import SwiftCoderTUI

final class LayoutTests: XCTestCase {

    // MARK: - Rect

    func testRectInsetUniform() {
        let r = Rect(x: 0, y: 0, width: 10, height: 6)
        let inner = r.inset(by: 1)
        XCTAssertEqual(inner, Rect(x: 1, y: 1, width: 8, height: 4))
    }

    func testRectInsetPerSide() {
        let r = Rect(x: 0, y: 0, width: 80, height: 24)
        let inner = r.inset(top: 1, left: 2, bottom: 1, right: 2)
        XCTAssertEqual(inner, Rect(x: 2, y: 1, width: 76, height: 22))
    }

    func testRectInsetClampsToZero() {
        let r = Rect(x: 0, y: 0, width: 4, height: 4)
        let inner = r.inset(by: 10)
        XCTAssertEqual(inner.width, 0)
        XCTAssertEqual(inner.height, 0)
    }

    func testRectArea() {
        let r = Rect(x: 0, y: 0, width: 10, height: 5)
        XCTAssertEqual(r.area, 50)
    }

    func testRectZero() {
        XCTAssertEqual(Rect.zero, Rect(x: 0, y: 0, width: 0, height: 0))
    }

    // MARK: - StackLayout (horizontal)

    func testStackLayoutFixedFlexFixed() {
        let layout = StackLayout(
            axis: .horizontal,
            items: [.fixed(10), .flex(1), .fixed(5)]
        )
        let bounds = Rect(x: 0, y: 0, width: 30, height: 10)
        let rects = layout.compute(in: bounds)

        XCTAssertEqual(rects.count, 3)
        // fixed(10) → x=0, w=10
        XCTAssertEqual(rects[0], Rect(x: 0,  y: 0, width: 10, height: 10))
        // flex(1) gets remaining 30-10-5=15 → x=10, w=15
        XCTAssertEqual(rects[1], Rect(x: 10, y: 0, width: 15, height: 10))
        // fixed(5) → x=25, w=5
        XCTAssertEqual(rects[2], Rect(x: 25, y: 0, width: 5,  height: 10))
    }

    func testStackLayoutWithSpacing() {
        let layout = StackLayout(
            axis: .horizontal,
            items: [.fixed(10), .fixed(10)],
            spacing: 2
        )
        let bounds = Rect(x: 0, y: 0, width: 30, height: 5)
        let rects = layout.compute(in: bounds)

        XCTAssertEqual(rects[0], Rect(x: 0,  y: 0, width: 10, height: 5))
        // spacing(2) between items → x = 10+2=12
        XCTAssertEqual(rects[1], Rect(x: 12, y: 0, width: 10, height: 5))
    }

    func testStackLayoutVertical() {
        let layout = StackLayout(
            axis: .vertical,
            items: [.fixed(5), .flex(1), .fixed(3)]
        )
        let bounds = Rect(x: 0, y: 0, width: 20, height: 20)
        let rects = layout.compute(in: bounds)

        XCTAssertEqual(rects[0], Rect(x: 0, y: 0,  width: 20, height: 5))
        XCTAssertEqual(rects[1], Rect(x: 0, y: 5,  width: 20, height: 12))
        XCTAssertEqual(rects[2], Rect(x: 0, y: 17, width: 20, height: 3))
    }

    func testStackLayoutEmpty() {
        let layout = StackLayout(axis: .horizontal, items: [])
        let rects = layout.compute(in: Rect(x: 0, y: 0, width: 80, height: 24))
        XCTAssertEqual(rects, [])
    }

    // MARK: - SplitLayout

    func testSplitLayoutHorizontalHalfHalf() {
        let bounds = Rect(x: 0, y: 0, width: 40, height: 10)
        let (left, right) = SplitLayout.horizontal(
            left: .flex(1), right: .flex(1), in: bounds
        )
        XCTAssertEqual(left,  Rect(x: 0,  y: 0, width: 20, height: 10))
        XCTAssertEqual(right, Rect(x: 20, y: 0, width: 20, height: 10))
    }

    func testSplitLayoutHorizontalFixedAndFlex() {
        let bounds = Rect(x: 0, y: 0, width: 80, height: 24)
        let (left, right) = SplitLayout.horizontal(
            left: .fixed(30), right: .flex(1), in: bounds
        )
        XCTAssertEqual(left,  Rect(x: 0,  y: 0, width: 30, height: 24))
        XCTAssertEqual(right, Rect(x: 30, y: 0, width: 50, height: 24))
    }

    func testSplitLayoutVertical() {
        let bounds = Rect(x: 0, y: 0, width: 80, height: 20)
        let (top, bottom) = SplitLayout.vertical(
            top: .fixed(5), bottom: .flex(1), in: bounds
        )
        XCTAssertEqual(top,    Rect(x: 0, y: 0, width: 80, height: 5))
        XCTAssertEqual(bottom, Rect(x: 0, y: 5, width: 80, height: 15))
    }
}
