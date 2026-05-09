import XCTest
@testable import SwiftCoderTUI

final class RendererModelCommandTests: XCTestCase {
    private static let config = AppConfig(
        appName: "Test",
        version: "0.0.1",
        welcomeMessage: "testing",
        models: [
            AppConfig.ModelConfig(id: "apex-ultra", label: "apex-ultra"),
            AppConfig.ModelConfig(id: "apex-swift", label: "apex-swift"),
            AppConfig.ModelConfig(id: "nova-coder", label: "nova-coder"),
        ],
        modes: [
            AppConfig.ModeConfig(id: "minimal", label: "minimal", barColor: "", badgeColor: ""),
        ],
        commands: [
            AppConfig.CommandConfig(name: "/model", description: "Switch model"),
        ]
    )

    func testSetCurrentModelIndexClampsAndUpdatesSelection() async {
        let term = VirtualTerminal(rows: 20, cols: 80)
        let renderer = Renderer(config: Self.config, terminal: term)

        await renderer.setCurrentModelIndex(2)
        let selectedThird = await renderer.getCurrentModelLabel()
        XCTAssertEqual(selectedThird, "nova-coder")

        await renderer.setCurrentModelIndex(999)
        let clampedHigh = await renderer.getCurrentModelLabel()
        XCTAssertEqual(clampedHigh, "nova-coder")

        await renderer.setCurrentModelIndex(-1)
        let clampedLow = await renderer.getCurrentModelLabel()
        XCTAssertEqual(clampedLow, "apex-ultra")
    }

    func testCustomCommandPaletteMatchesSlashMenuSelectionFlow() async {
        let term = VirtualTerminal(rows: 20, cols: 80)
        let renderer = Renderer(config: Self.config, terminal: term)

        await renderer.openCommandPalette(commands: [
            (name: "/model apex-ultra", desc: "Switch to apex-ultra"),
            (name: "/model nova-coder", desc: "Switch to nova-coder"),
        ])

        let isActive = await renderer.isAutocompleteActive()
        XCTAssertTrue(isActive)
        let selectedBefore = await renderer.getSelectedAutocompleteCommand()
        XCTAssertEqual(selectedBefore, "/model apex-ultra")

        await renderer.moveAutocompleteSelection(offset: 1)
        let selectedAfter = await renderer.getSelectedAutocompleteCommand()
        XCTAssertEqual(selectedAfter, "/model nova-coder")
    }
}
