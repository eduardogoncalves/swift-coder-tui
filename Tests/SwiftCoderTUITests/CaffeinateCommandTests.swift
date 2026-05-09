import XCTest
@testable import SwiftCoderTUI

final class CaffeinateCommandTests: XCTestCase {

    // MARK: - Parser: command routing

    func testResolveReturnsNilForNonCaffeinateCommands() {
        XCTAssertNil(CaffeinateCommandParser.resolve(input: "/clear"))
        XCTAssertNil(CaffeinateCommandParser.resolve(input: "/model on"))
        XCTAssertNil(CaffeinateCommandParser.resolve(input: "hello world"))
        XCTAssertNil(CaffeinateCommandParser.resolve(input: ""))
    }

    func testResolveReturnsOpenMenuWhenNoArgumentProvided() {
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate"), .openMenu)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: " /caffeinate  "), .openMenu)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate "), .openMenu)
    }

    func testResolveOnOffBusyCaseInsensitively() {
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate on"),   .on)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate ON"),   .on)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate off"),  .off)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate OFF"),  .off)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate busy"), .busy)
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate BUSY"), .busy)
    }

    func testResolveInvalidArgumentReturnsInvalid() {
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate notacommand"), .invalid("notacommand"))
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate 0"), .invalid("0"))
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate -5"), .invalid("-5"))
    }

    // MARK: - Parser: duration parsing

    func testParseDurationSeconds() {
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("30"),  30)
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("30s"), 30)
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("30S"), 30)
    }

    func testParseDurationMinutes() {
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("30m"),  1_800)
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("30M"),  1_800)
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("1m"),   60)
    }

    func testParseDurationHours() {
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("1h"),  3_600)
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("2H"),  7_200)
        XCTAssertEqual(CaffeinateCommandParser.parseDuration("2h"),  7_200)
    }

    func testParseDurationRejectsInvalidValues() {
        XCTAssertNil(CaffeinateCommandParser.parseDuration("abc"))
        XCTAssertNil(CaffeinateCommandParser.parseDuration("0"))
        XCTAssertNil(CaffeinateCommandParser.parseDuration("-1"))
        XCTAssertNil(CaffeinateCommandParser.parseDuration(""))
    }

    func testResolveDurationViaCommand() {
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate 30m"),  .duration(seconds: 1_800))
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate 1h"),   .duration(seconds: 3_600))
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate 3600"), .duration(seconds: 3_600))
        XCTAssertEqual(CaffeinateCommandParser.resolve(input: "/caffeinate 2H"),   .duration(seconds: 7_200))
    }

    // MARK: - Parser: menu items

    func testMenuItemsContainsExpectedOptions() {
        let items = CaffeinateCommandParser.menuItems()
        let names = items.map(\.name)
        XCTAssertTrue(names.contains("/caffeinate on"))
        XCTAssertTrue(names.contains("/caffeinate off"))
        XCTAssertTrue(names.contains("/caffeinate busy"))
        XCTAssertFalse(names.isEmpty)
    }

    // MARK: - SlashCommand autocomplete

    func testArgumentCompletionsShowAllWhenPrefixIsEmpty() {
        let cmd = CaffeinateSlashCommand()
        let items = cmd.argumentCompletions(prefix: "")
        XCTAssertFalse(items.isEmpty)
        let labels = items.map(\.label)
        XCTAssertTrue(labels.contains("/caffeinate on"))
        XCTAssertTrue(labels.contains("/caffeinate off"))
        XCTAssertTrue(labels.contains("/caffeinate busy"))
    }

    func testArgumentCompletionsFiltersOnPrefix() {
        let cmd = CaffeinateSlashCommand()
        let items = cmd.argumentCompletions(prefix: "o")
        let labels = items.map(\.label)
        XCTAssertTrue(labels.contains("/caffeinate on"))
        XCTAssertTrue(labels.contains("/caffeinate off"))
        XCTAssertFalse(labels.contains("/caffeinate busy"))
    }

    func testArgumentCompletionsReturnsNothingForNonMatchingPrefix() {
        let cmd = CaffeinateSlashCommand()
        let items = cmd.argumentCompletions(prefix: "zzz")
        XCTAssertTrue(items.isEmpty)
    }

    func testExpandsInlineWhenNoArgIsFalseByDefault() {
        // /caffeinate appears as a single entry in the / menu; sub-options surface
        // only after a space (argument completion) or via the command palette.
        XCTAssertFalse(CaffeinateSlashCommand().expandsInlineWhenNoArg)
    }

    // MARK: - Slash menu via CombinedAutocompleteProvider

    func testMainSlashMenuShowsSingleCaffeinateEntry() {
        let provider = CombinedAutocompleteProvider(commands: [CaffeinateSlashCommand()])
        let suggestion = provider.getSuggestions(lines: ["/"], cursorLine: 0, cursorCol: 1)
        XCTAssertNotNil(suggestion)
        let labels = suggestion!.items.map(\.label)
        // Single collapsed entry, not the six sub-options
        XCTAssertTrue(labels.contains("/caffeinate"))
        XCTAssertFalse(labels.contains("/caffeinate on"))
        XCTAssertFalse(labels.contains("/caffeinate off"))
    }

    func testPostSpaceArgumentCompletionShowsSubOptions() {
        let provider = CombinedAutocompleteProvider(commands: [CaffeinateSlashCommand()])
        let suggestion = provider.getSuggestions(lines: ["/caffeinate "], cursorLine: 0, cursorCol: 12)
        XCTAssertNotNil(suggestion)
        let labels = suggestion!.items.map(\.label)
        XCTAssertTrue(labels.contains("/caffeinate on"))
        XCTAssertTrue(labels.contains("/caffeinate off"))
        XCTAssertTrue(labels.contains("/caffeinate busy"))
    }

    func testPostSpaceArgumentCompletionFiltersOnArg() {
        let provider = CombinedAutocompleteProvider(commands: [CaffeinateSlashCommand()])
        let suggestion = provider.getSuggestions(lines: ["/caffeinate b"], cursorLine: 0, cursorCol: 13)
        XCTAssertNotNil(suggestion)
        let labels = suggestion!.items.map(\.label)
        XCTAssertTrue(labels.contains("/caffeinate busy"))
        XCTAssertFalse(labels.contains("/caffeinate on"))
    }

    func testSlashCommandNameAndDescription() {
        let cmd = CaffeinateSlashCommand()
        XCTAssertEqual(cmd.name, "caffeinate")
        XCTAssertNotNil(cmd.description)
    }
}
