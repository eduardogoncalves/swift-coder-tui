import XCTest
@testable import SwiftCoderTUI

final class RendererFooterModeTests: XCTestCase {
    private static let config = AppConfig(
        appName: "Test",
        version: "0.0.1",
        welcomeMessage: "testing",
        models: [AppConfig.ModelConfig(id: "model", label: "Model-X")],
        modes: [
            AppConfig.ModeConfig(id: "fast", label: "FAST", barColor: "", badgeColor: ""),
            AppConfig.ModeConfig(id: "safe", label: "SAFE", barColor: "", badgeColor: ""),
        ],
        commands: []
    )

    private func renderToScreen(_ output: String, rows: Int, cols: Int) -> [[Character]] {
        var screen = Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        var curRow = 0
        var curCol = 0

        let scalars = Array(output.unicodeScalars)
        var i = 0

        func writeScalar(_ sv: Unicode.Scalar) {
            guard curRow >= 0, curRow < rows, curCol >= 0, curCol < cols else { return }
            screen[curRow][curCol] = Character(sv)
            curCol += 1
        }

        func isFinalByte(_ v: UInt32) -> Bool { v >= 0x40 && v <= 0x7E }

        while i < scalars.count {
            let sv = scalars[i]

            if sv.value == 0x1B {
                guard i + 1 < scalars.count else { break }
                if scalars[i + 1].value == 0x5B {
                    var params = ""
                    var j = i + 2
                    while j < scalars.count && !isFinalByte(scalars[j].value) {
                        params.append(Character(scalars[j]))
                        j += 1
                    }
                    let cmd = j < scalars.count ? Character(scalars[j]) : "?"
                    i = j < scalars.count ? j + 1 : j

                    switch cmd {
                    case "A":
                        let n = Int(params) ?? 1
                        curRow = max(0, curRow - n)
                    case "G":
                        let n = (Int(params) ?? 1) - 1
                        curCol = max(0, min(cols - 1, n))
                    case "H":
                        let parts = params.split(separator: ";").compactMap { Int($0) }
                        curRow = max(0, min(rows - 1, (parts.count > 0 ? parts[0] : 1) - 1))
                        curCol = max(0, min(cols - 1, (parts.count > 1 ? parts[1] : 1) - 1))
                    case "J":
                        if params == "0" || params == "" {
                            for c in curCol..<cols { screen[curRow][c] = " " }
                            for r in (curRow + 1)..<rows { for c in 0..<cols { screen[r][c] = " " } }
                        } else if params == "2" {
                            for r in 0..<rows { for c in 0..<cols { screen[r][c] = " " } }
                        }
                    case "K":
                        if params == "2" {
                            for c in 0..<cols { screen[curRow][c] = " " }
                        } else {
                            for c in curCol..<cols { screen[curRow][c] = " " }
                        }
                    default:
                        break
                    }
                } else if scalars[i + 1].value == 0x5D {
                    var j = i + 2
                    while j < scalars.count && scalars[j].value != 0x07 { j += 1 }
                    i = j < scalars.count ? j + 1 : j
                } else {
                    i += 1
                }
                continue
            }

            switch sv.value {
            case 0x0D:
                curCol = 0
            case 0x0A:
                if curRow + 1 < rows {
                    curRow += 1
                } else {
                    for r in 0..<rows - 1 { screen[r] = screen[r + 1] }
                    screen[rows - 1] = Array(repeating: " ", count: cols)
                }
            default:
                writeScalar(sv)
            }
            i += 1
        }
        return screen
    }

    func testFooterRightSideUsesSingleActiveModeFormat() async {
        let fileManager = FileManager.default
        let originalCwd = fileManager.currentDirectoryPath
        XCTAssertTrue(fileManager.changeCurrentDirectoryPath("/"))
        defer { _ = fileManager.changeCurrentDirectoryPath(originalCwd) }

        let terminal = VirtualTerminal(rows: 12, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: terminal)

        await renderer.setContextPercent(1.0)
        await renderer.setupScreen()
        await renderer.renderFooter()

        let screen = renderToScreen(terminal.output, rows: 12, cols: 120)
        let rendered = screen.map { String($0) }.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("[Model-X](FAST)"), rendered)
        XCTAssertFalse(rendered.contains("FAST|SAFE"), rendered)
    }

    func testFooterRightSideTracksCurrentActiveMode() async {
        let fileManager = FileManager.default
        let originalCwd = fileManager.currentDirectoryPath
        XCTAssertTrue(fileManager.changeCurrentDirectoryPath("/"))
        defer { _ = fileManager.changeCurrentDirectoryPath(originalCwd) }

        let terminal = VirtualTerminal(rows: 12, cols: 120)
        let renderer = Renderer(config: Self.config, terminal: terminal)

        await renderer.setContextPercent(1.0)
        await renderer.setupScreen()
        await renderer.setCurrentModeIndex(1)
        await renderer.renderFooter()

        let screen = renderToScreen(terminal.output, rows: 12, cols: 120)
        let rendered = screen.map { String($0) }.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("[Model-X](SAFE)"), rendered)
        XCTAssertFalse(rendered.contains("FAST|SAFE"), rendered)
    }

    func testFooterKeepsActiveModeVisibleWhenSpaceIsTight() async {
        let compactConfig = AppConfig(
            appName: "Test",
            version: "0.0.1",
            welcomeMessage: "testing",
            models: [AppConfig.ModelConfig(id: "apex-swift-ultra-long-model-name", label: "apex-swift-ultra-long-model-name")],
            modes: [
                AppConfig.ModeConfig(id: "fast", label: "FAST", barColor: "", badgeColor: ""),
                AppConfig.ModeConfig(id: "safe", label: "SAFE", barColor: "", badgeColor: ""),
            ],
            commands: []
        )
        let fileManager = FileManager.default
        let originalCwd = fileManager.currentDirectoryPath
        XCTAssertTrue(fileManager.changeCurrentDirectoryPath("/"))
        defer { _ = fileManager.changeCurrentDirectoryPath(originalCwd) }

        let terminal = VirtualTerminal(rows: 12, cols: 88)
        let renderer = Renderer(config: compactConfig, terminal: terminal)

        await renderer.setContextPercent(100.0)
        await renderer.setSandboxEnabled(true)
        await renderer.setCurrentModeIndex(1)
        await renderer.setupScreen()
        await renderer.renderFooter()

        let screen = renderToScreen(terminal.output, rows: 12, cols: 88)
        let rendered = screen.map { String($0) }.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("(SAFE)"), rendered)
        XCTAssertFalse(rendered.contains("FAST|SAFE"), rendered)
    }
}
