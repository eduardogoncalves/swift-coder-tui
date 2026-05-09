import XCTest
@testable import SwiftCoderTUI

final class StreamFormatterTests: XCTestCase {

    // MARK: - Helpers

    private func makeFormatter() -> StreamFormatter {
        StreamFormatter()
    }

    // MARK: - 1. Plain line outside a code block

    func testPlainLineReturnedUnchanged() {
        let fmt = makeFormatter()
        let line = "Hello, world!"
        XCTAssertEqual(fmt.format(line), line)
    }

    // MARK: - 2. Opening ```swift fence

    func testOpeningFenceReturnsStyledHeader() {
        let fmt = makeFormatter()
        let result = fmt.format("```swift")
        XCTAssertTrue(result.contains("swift"), "Header should contain language name")
        XCTAssertTrue(result.contains("╭"), "Header should contain opening corner")
        XCTAssertTrue(result.contains(DesignSystem.reset), "Header should end with reset")
    }

    func testOpeningFenceSetsInCodeBlockState() {
        let fmt = makeFormatter()
        _ = fmt.format("```swift")
        // A code line after the fence should be styled (not returned verbatim)
        let codeLine = "let x = 1"
        let result = fmt.format(codeLine)
        XCTAssertNotEqual(result, codeLine, "Code line inside block should be styled")
    }

    // MARK: - 3. Code line inside block has indent and color codes

    func testCodeLineInsideBlockHasIndentAndReset() {
        let fmt = makeFormatter()
        _ = fmt.format("```swift")
        let result = fmt.format("let x = 1")
        XCTAssertTrue(result.hasPrefix("  ") || result.contains("  "),
                      "Code line should be indented")
        XCTAssertTrue(result.contains(DesignSystem.reset),
                      "Code line should contain reset sequence")
        XCTAssertTrue(result.contains("\u{1B}["),
                      "Code line should contain ANSI escape code")
    }

    // MARK: - 4. Closing fence returns styled footer

    func testClosingFenceReturnsStyledFooter() {
        let fmt = makeFormatter()
        _ = fmt.format("```swift")
        let result = fmt.format("```")
        XCTAssertTrue(result.contains("╰"), "Footer should contain closing corner")
        XCTAssertTrue(result.contains(DesignSystem.reset), "Footer should end with reset")
    }

    func testClosingFenceClearsInCodeBlockState() {
        let fmt = makeFormatter()
        _ = fmt.format("```swift")
        _ = fmt.format("```")
        // After closing, a line should be returned unchanged
        let plain = "Normal text again"
        XCTAssertEqual(fmt.format(plain), plain)
    }

    // MARK: - 5. Diff + line → green

    func testDiffPlusLineContainsGreen() {
        let fmt = makeFormatter()
        _ = fmt.format("```diff")
        let result = fmt.format("+added line")
        XCTAssertTrue(result.contains(DesignSystem.green),
                      "Diff + line should contain green color")
    }

    // MARK: - 6. Diff - line → red

    func testDiffMinusLineContainsRed() {
        let fmt = makeFormatter()
        _ = fmt.format("```diff")
        let result = fmt.format("-removed line")
        XCTAssertTrue(result.contains(DesignSystem.red),
                      "Diff - line should contain red color")
    }

    // MARK: - 7. Diff @@ line → brightCyan

    func testDiffHunkHeaderContainsBrightCyan() {
        let fmt = makeFormatter()
        _ = fmt.format("```diff")
        let result = fmt.format("@@ -1,3 +1,4 @@")
        XCTAssertTrue(result.contains(DesignSystem.brightCyan),
                      "Diff @@ line should contain brightCyan color")
    }

    // MARK: - 8. reset() clears state

    func testResetClearsCodeBlockState() {
        let fmt = makeFormatter()
        _ = fmt.format("```swift")
        fmt.reset()
        // After reset, a plain line should be returned unchanged
        let plain = "not code"
        XCTAssertEqual(fmt.format(plain), plain,
                       "After reset(), lines should not be styled as code")
    }

    // MARK: - 9. Consecutive fences

    func testConsecutiveFencesWorkCorrectly() {
        let fmt = makeFormatter()

        // First block
        let open1 = fmt.format("```swift")
        XCTAssertTrue(open1.contains("╭"))
        let code1 = fmt.format("let a = 1")
        XCTAssertNotEqual(code1, "let a = 1")
        let close1 = fmt.format("```")
        XCTAssertTrue(close1.contains("╰"))

        // Between blocks — plain text
        let between = fmt.format("Some prose")
        XCTAssertEqual(between, "Some prose")

        // Second block
        let open2 = fmt.format("```python")
        XCTAssertTrue(open2.contains("╭"))
        XCTAssertTrue(open2.contains("python"))
        let code2 = fmt.format("print('hi')")
        XCTAssertNotEqual(code2, "print('hi')")
        let close2 = fmt.format("```")
        XCTAssertTrue(close2.contains("╰"))

        // After second block — plain text
        let after = fmt.format("More prose")
        XCTAssertEqual(after, "More prose")
    }

    // MARK: - 10. ``` with no language

    func testFenceWithNoLanguageOpensAndClosesCorrectly() {
        let fmt = makeFormatter()

        let openResult = fmt.format("```")
        XCTAssertTrue(openResult.contains("╭"), "No-language fence should still open")

        let codeLine = "some code"
        let styledCode = fmt.format(codeLine)
        XCTAssertNotEqual(styledCode, codeLine, "Lines inside no-lang block should be styled")

        let closeResult = fmt.format("```")
        XCTAssertTrue(closeResult.contains("╰"), "Should close correctly")

        // Now we're outside — plain text
        XCTAssertEqual(fmt.format("plain"), "plain")
    }

    // MARK: - Diff --- and +++ lines → dim

    func testDiffTriplePlusLineDim() {
        let fmt = makeFormatter()
        _ = fmt.format("```diff")
        let result = fmt.format("+++ b/file.swift")
        XCTAssertTrue(result.contains(DesignSystem.dim),
                      "+++ line should use dim style, not green")
        XCTAssertFalse(result.contains(DesignSystem.green),
                       "+++ line should not be green")
    }

    func testDiffTripleMinusLineDim() {
        let fmt = makeFormatter()
        _ = fmt.format("```diff")
        let result = fmt.format("--- a/file.swift")
        XCTAssertTrue(result.contains(DesignSystem.dim),
                      "--- line should use dim style, not red")
        XCTAssertFalse(result.contains(DesignSystem.red),
                       "--- line should not be red")
    }
}
