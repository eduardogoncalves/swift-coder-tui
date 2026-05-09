import XCTest
@testable import SwiftCoderTUI

final class ColorTests: XCTestCase {

    // MARK: - hex(_:String) constructor

    func testHexWithHashPrefix() {
        XCTAssertEqual(Color.hex("#ff0000"), .rgb(255, 0, 0))
    }

    func testHexWithoutHashPrefix() {
        XCTAssertEqual(Color.hex("00ff00"), .rgb(0, 255, 0))
    }

    func testHexBlue() {
        XCTAssertEqual(Color.hex("#0000ff"), .rgb(0, 0, 255))
    }

    func testHexBlack() {
        XCTAssertEqual(Color.hex("#000000"), .rgb(0, 0, 0))
    }

    func testHexWhite() {
        XCTAssertEqual(Color.hex("#ffffff"), .rgb(255, 255, 255))
    }

    func testHexCaseInsensitive() {
        XCTAssertEqual(Color.hex("#FF0000"), .rgb(255, 0, 0))
    }

    func testHexInvalidReturnsBlack() {
        XCTAssertEqual(Color.hex("xyz"), .rgb(0, 0, 0))
    }

    // MARK: - hex(_:UInt32) constructor

    func testHexUInt32() {
        XCTAssertEqual(Color.hex(0xFF0000), .rgb(255, 0, 0))
    }

    // MARK: - lerp

    func testLerpAtZeroReturnsA() {
        let result = Color.lerp(.rgb(10, 20, 30), .rgb(100, 200, 255), phase: 0)
        XCTAssertEqual(result, .rgb(10, 20, 30))
    }

    func testLerpAtOneReturnsB() {
        let result = Color.lerp(.rgb(10, 20, 30), .rgb(100, 200, 255), phase: 1)
        XCTAssertEqual(result, .rgb(100, 200, 255))
    }

    func testLerpMidpointBlackToWhite() {
        // 0 + (255-0)*0.5 = 127.5 → rounds to 128 (banker's rounding, 128 is even)
        let result = Color.lerp(.rgb(0, 0, 0), .rgb(255, 255, 255), phase: 0.5)
        XCTAssertEqual(result, .rgb(128, 128, 128))
    }

    func testLerpClampsBelowZero() {
        let result = Color.lerp(.rgb(0, 0, 0), .rgb(255, 255, 255), phase: -1)
        XCTAssertEqual(result, .rgb(0, 0, 0))
    }

    func testLerpClampsAboveOne() {
        let result = Color.lerp(.rgb(0, 0, 0), .rgb(255, 255, 255), phase: 2)
        XCTAssertEqual(result, .rgb(255, 255, 255))
    }

    // MARK: - lighter / darker

    func testLighterIncreasesLightness() {
        let dark = Color.rgb(50, 50, 50)
        let lighter = dark.lighter(by: 0.5)
        guard case .rgb(let r, let g, let b) = lighter,
              case .rgb(let dr, let dg, let db) = dark else {
            XCTFail("Expected rgb colors")
            return
        }
        XCTAssertGreaterThan(Int(r) + Int(g) + Int(b), Int(dr) + Int(dg) + Int(db))
    }

    func testDarkerDecreasesLightness() {
        let light = Color.rgb(200, 200, 200)
        let darker = light.darker(by: 0.5)
        guard case .rgb(let r, let g, let b) = darker,
              case .rgb(let lr, let lg, let lb) = light else {
            XCTFail("Expected rgb colors")
            return
        }
        XCTAssertLessThan(Int(r) + Int(g) + Int(b), Int(lr) + Int(lg) + Int(lb))
    }

    // MARK: - foregroundSGR / backgroundSGR

    func testAnsiForegroundSGR() {
        // red rawValue=1, code=30+1=31
        XCTAssertEqual(Color.ansi(.red).foregroundSGR,   "\u{1B}[31m")
        // green rawValue=2, code=30+2=32
        XCTAssertEqual(Color.ansi(.green).foregroundSGR, "\u{1B}[32m")
        // black rawValue=0, code=30+0=30
        XCTAssertEqual(Color.ansi(.black).foregroundSGR, "\u{1B}[30m")
    }

    func testAnsiBackgroundSGR() {
        // red rawValue=1, code=40+1=41
        XCTAssertEqual(Color.ansi(.red).backgroundSGR, "\u{1B}[41m")
    }

    func testRGBForegroundSGR() {
        XCTAssertEqual(Color.rgb(255, 0, 0).foregroundSGR, "\u{1B}[38;2;255;0;0m")
    }

    func testRGBBackgroundSGR() {
        XCTAssertEqual(Color.rgb(0, 255, 0).backgroundSGR, "\u{1B}[48;2;0;255;0m")
    }

    func testXtermForegroundSGR() {
        XCTAssertEqual(Color.xterm(200).foregroundSGR, "\u{1B}[38;5;200m")
    }

    func testXtermBackgroundSGR() {
        XCTAssertEqual(Color.xterm(42).backgroundSGR, "\u{1B}[48;5;42m")
    }

    // MARK: - Bright colours (rawValue >= 8 uses offset 82 fg / 92 bg)

    func testBrightRedForegroundSGR() {
        // brightRed rawValue=9, code=82+9=91
        XCTAssertEqual(Color.ansi(.brightRed).foregroundSGR, "\u{1B}[91m")
    }

    // MARK: - Reset sequences

    func testResetSGR() {
        XCTAssertEqual(Color.reset, "\u{1B}[0m")
    }

    func testResetForeground() {
        XCTAssertEqual(Color.resetForeground, "\u{1B}[39m")
    }

    func testResetBackground() {
        XCTAssertEqual(Color.resetBackground, "\u{1B}[49m")
    }
}
