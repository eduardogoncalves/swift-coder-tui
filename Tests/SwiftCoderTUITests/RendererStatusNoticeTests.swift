import XCTest
@testable import SwiftCoderTUI

final class RendererStatusNoticeTests: XCTestCase {
    private static let config = AppConfig(
        appName: "Test",
        version: "0.0.1",
        welcomeMessage: "testing",
        models: [AppConfig.ModelConfig(id: "model", label: "Model-X")],
        modes: [
            AppConfig.ModeConfig(id: "fast", label: "FAST", barColor: "", badgeColor: ""),
        ],
        commands: []
    )

    /// Strip ANSI CSI sequences so we can assert against plain text.
    private func stripAnsi(_ s: String) -> String {
        var out = ""
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let v = scalars[i].value
            if v == 0x1B, i + 1 < scalars.count, scalars[i + 1].value == 0x5B {
                var j = i + 2
                while j < scalars.count {
                    let c = scalars[j].value
                    if c >= 0x40 && c <= 0x7E { j += 1; break }
                    j += 1
                }
                i = j
                continue
            }
            out.unicodeScalars.append(scalars[i])
            i += 1
        }
        return out
    }

    func testStatusNoticeRendersInFooterWithoutSpinnerOrEscSuffix() async {
        let terminal = VirtualTerminal(rows: 20, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: terminal)

        await renderer.setupScreen()
        await renderer.setStatusNotice("🎤 Listening… press Enter to finish")
        await renderer.renderFooter()

        let plain = stripAnsi(terminal.output)
        XCTAssertTrue(plain.contains("🎤 Listening… press Enter to finish"), plain)
        // Must not be framed with the generation spinner artifacts.
        XCTAssertFalse(plain.contains("(esc · 0s)"), plain)
    }

    func testStatusNoticeCoexistsWithGenerationSpinner() async {
        let terminal = VirtualTerminal(rows: 20, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: terminal)

        await renderer.setupScreen()
        await renderer.setStatusNotice("notice-here")
        await renderer.setGenerating(true)
        await renderer.setThinking("Thinking")
        await renderer.renderFooter()

        let plain = stripAnsi(terminal.output)
        XCTAssertTrue(plain.contains("notice-here"), plain)
        XCTAssertTrue(plain.contains("Thinking"), plain)
        XCTAssertTrue(plain.contains("(esc ·"), plain)
    }

    func testClearStatusNoticeRemovesItFromFooter() async {
        let terminal = VirtualTerminal(rows: 20, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: terminal)

        await renderer.setupScreen()
        await renderer.setStatusNotice("ephemeral-notice")
        await renderer.renderFooter()
        XCTAssertTrue(stripAnsi(terminal.output).contains("ephemeral-notice"))

        await renderer.setStatusNotice(nil)
        // Capture only output produced after clearing.
        let before = terminal.output.count
        await renderer.renderFooter()
        let tail = String(terminal.output.suffix(terminal.output.count - before))
        XCTAssertFalse(stripAnsi(tail).contains("ephemeral-notice"), tail)
    }

    func testEmptyStringClearsNotice() async {
        let terminal = VirtualTerminal(rows: 20, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: terminal)

        await renderer.setupScreen()
        await renderer.setStatusNotice("first")
        await renderer.setStatusNotice("")
        let before = terminal.output.count
        await renderer.renderFooter()
        let tail = String(terminal.output.suffix(terminal.output.count - before))
        XCTAssertFalse(stripAnsi(tail).contains("first"), tail)
    }
}
