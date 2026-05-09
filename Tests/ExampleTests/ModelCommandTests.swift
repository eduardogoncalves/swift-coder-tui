import XCTest
@testable import Example
import SwiftCoderTUI

final class ModelCommandTests: XCTestCase {
    private static let models: [AppConfig.ModelConfig] = [
        AppConfig.ModelConfig(id: "apex-ultra", label: "apex-ultra"),
        AppConfig.ModelConfig(id: "apex-swift", label: "Apex Swift"),
        AppConfig.ModelConfig(id: "nova-coder", label: "nova-coder"),
    ]

    func testResolveReturnsOpenMenuWhenNoArgumentProvided() {
        XCTAssertEqual(
            ModelCommandParser.resolve(input: "/model", models: Self.models),
            .openMenu
        )
        XCTAssertEqual(
            ModelCommandParser.resolve(input: " /model   ", models: Self.models),
            .openMenu
        )
    }

    func testResolveSelectsModelByLabelOrIdCaseInsensitively() {
        XCTAssertEqual(
            ModelCommandParser.resolve(input: "/model apex-ultra", models: Self.models),
            .selectModel(index: 0)
        )
        XCTAssertEqual(
            ModelCommandParser.resolve(input: "/model APEX SWIFT", models: Self.models),
            .selectModel(index: 1)
        )
        XCTAssertEqual(
            ModelCommandParser.resolve(input: "/model NOVA-CODER", models: Self.models),
            .selectModel(index: 2)
        )
    }

    func testResolveReturnsInvalidForUnknownModelName() {
        XCTAssertEqual(
            ModelCommandParser.resolve(input: "/model not-a-model", models: Self.models),
            .invalidModelName("not-a-model")
        )
    }

    func testResolveIgnoresNonModelCommands() {
        XCTAssertNil(ModelCommandParser.resolve(input: "/mode high", models: Self.models))
        XCTAssertNil(ModelCommandParser.resolve(input: "hello", models: Self.models))
    }

    func testMenuItemsAreRenderedAsModelCommands() {
        let items = ModelCommandParser.menuItems(models: Self.models, currentModelLabel: "Apex Swift")

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].name, "/model apex-ultra")
        XCTAssertEqual(items[1].name, "/model Apex Swift")
        XCTAssertEqual(items[1].desc, "Current model")
    }

    func testModelSlashCommandSuggestionsIncludeModelCommandLabels() {
        let command = ModelSlashCommand(models: Self.models)

        let suggestions = command.argumentCompletions(prefix: "ap")
        XCTAssertEqual(suggestions.map(\.label), ["/model apex-ultra", "/model Apex Swift"])
        XCTAssertEqual(suggestions.map(\.value), ["apex-ultra", "Apex Swift"])
    }
}
