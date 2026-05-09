import XCTest
@testable import SwiftCoderTUI

final class MarkdownTests: XCTestCase {

    // Use a fixed palette so tests don't depend on DesignSystem.currentTheme state.
    private let palette = Theme.classic.palette
    private var renderer: MarkdownRenderer { MarkdownRenderer(palette: palette, width: 80) }

    // MARK: - Bold

    func testBoldRenderingContainsSGR1() {
        let result = renderer.render("**bold**")
        // TextAttributes().bold() wraps with ESC[1m ... ESC[0m
        XCTAssertTrue(result.contains("\u{1B}[1m"), "bold text should open with SGR 1")
        XCTAssertTrue(result.contains("bold"))
        XCTAssertTrue(result.contains("\u{1B}[0m"), "bold text should close with SGR reset")
    }

    func testBoldRenderingExact() {
        // "**bold**" in a paragraph: inline → "\u{1B}[1mbold\u{1B}[0m",
        // word-wrapped (no break needed), trailing empty stripped.
        let result = renderer.render("**bold**")
        XCTAssertEqual(result, "\u{1B}[1mbold\u{1B}[0m")
    }

    // MARK: - Italic

    func testItalicRenderingContainsSGR3() {
        let result = renderer.render("*italic*")
        XCTAssertTrue(result.contains("\u{1B}[3m"), "italic text should open with SGR 3")
        XCTAssertTrue(result.contains("italic"))
    }

    // MARK: - Heading

    func testHeadingContainsBold() {
        let result = renderer.render("# Hello")
        XCTAssertTrue(result.contains("Hello"))
        // H1 uses bold — the sequence starts with ESC[1
        XCTAssertTrue(result.contains("\u{1B}[1"), "heading should contain bold SGR")
        XCTAssertTrue(result.contains("\u{1B}[0m"))
    }

    func testH1UsesClassicAccentColor() {
        // classic palette accent = .ansi(.brightYellow) → rawValue 11, code 82+11=93
        let result = renderer.render("# Title")
        XCTAssertTrue(result.contains("93m") || result.contains("\u{1B}[1;93m"),
                      "H1 should use the accent color (brightYellow → 93)")
    }

    // MARK: - Link (OSC 8)

    func testLinkContainsOSC8() {
        let result = renderer.render("[link](http://example.com)")
        // OSC 8 escape: ESC ] 8 ; ; url ESC \\
        XCTAssertTrue(result.contains("\u{1B}]8;"),  "link should use OSC 8 escape")
        XCTAssertTrue(result.contains("http://example.com"))
        XCTAssertTrue(result.contains("link"))
    }

    func testLinkWithShortURL() {
        let result = renderer.render("[x](http://x)")
        XCTAssertTrue(result.contains("http://x"))
        XCTAssertTrue(result.contains("x"))
    }

    // MARK: - Inline code

    func testInlineCodeIsStyled() {
        let result = renderer.render("Use `foo()` here")
        XCTAssertTrue(result.contains("foo()"))
        // inline code applies background + foreground → some SGR sequence present
        XCTAssertTrue(result.contains("\u{1B}["))
    }

    // MARK: - Plain paragraph

    func testPlainParagraphPassesThrough() {
        let result = renderer.render("Hello, world!")
        XCTAssertTrue(result.contains("Hello, world!"))
    }
}
