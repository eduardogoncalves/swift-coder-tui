# SwiftCoderTUI

[![GitHub](https://img.shields.io/badge/GitHub-swift--coder--tui-181717?logo=github)](https://github.com/eduardogoncalves/swift-coder-tui)
[![Swift](https://img.shields.io/badge/Swift-6.3.1+-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015%2B-0A84FF)](https://github.com/eduardogoncalves/swift-coder-tui)
[![SPM](https://img.shields.io/badge/SPM-supported-FA7343?logo=swift)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Swift-native terminal UI toolkit for building coding assistants.

SwiftCoderTUI gives you a production-ready terminal shell for coder workflows: chat scrollback, streaming responses, code/diff-friendly rendering, slash command autocomplete, approval prompts, and status/footer controls. You bring your backend stream and tool execution logic.

## Why SwiftCoderTUI

- Built for coding assistants, not generic text UIs.
- Reusable Swift package, with a complete runnable Example app.
- Terminal-native behavior: raw input handling, bracketed paste, resize support, and ANSI-aware layout.
- Test-friendly architecture via a virtual terminal and focused unit tests.

## Features

- Renderer actor designed for chat-style coder flows.
- Footer/status model with model + mode badges, spinner, pending count, context %, sandbox badge, active file, and git branch.
- Streaming output pipeline with fenced code block and diff styling.
- Rich autocomplete with pluggable providers.
- Tool approval dialogs (accept, reject, autopilot-style flows).
- Markdown rendering via swift-markdown.
- Terminal abstraction:
  - ProcessTerminal for real TTY/raw mode.
  - VirtualTerminal for deterministic tests and snapshots.
- Optional diff-based full-screen renderer for viewport-driven UIs.

## Package Layout

- Sources/SwiftCoderTUI: library implementation.
- Example/Sources: complete sample app wired to mock streaming/tool events.
- Tests/SwiftCoderTUITests: unit tests across rendering, layout, markdown, diffing, width/wrapping, footer behavior, and terminal abstractions.

## Requirements

- Swift 6.3.1+
- macOS 15+

## Installation

### Swift Package Manager

Add SwiftCoderTUI to your package dependencies:

```swift
// swift-tools-version: 6.3.1
import PackageDescription

let package = Package(
    name: "MyCoderApp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/eduardogoncalves/swift-coder-tui.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "MyCoderApp",
            dependencies: [
                .product(name: "SwiftCoderTUI", package: "swift-coder-tui")
            ]
        )
    ]
)
```

If you are developing locally, use a local package path instead:

```swift
dependencies: [
    .package(path: "../swift-coder-tui")
]
```

## Quick Start

```swift
import Foundation
import SwiftCoderTUI

@main
struct MyApp {
    static let config = AppConfig(
        appName: "MyCodeAssistant",
        version: "1.0.0",
        welcomeMessage: "type a prompt and press Enter",
        models: [
            .init(id: "apex-ultra", label: "apex-ultra"),
            .init(id: "nova-coder", label: "nova-coder")
        ],
        modes: [
            .init(id: "minimal", label: "minimal", barColor: "\u{001B}[34m", badgeColor: "\u{001B}[34m"),
            .init(id: "high", label: "high", barColor: "\u{001B}[35m", badgeColor: "\u{001B}[95m")
        ],
        commands: [
            .init(name: "/clear", description: "Clear the conversation"),
            .init(name: "/model", description: "Switch model"),
            .init(name: "/help", description: "Show help")
        ],
        defaultModelIndex: 0,
        defaultModeIndex: 0
    )

    static let terminal = ProcessTerminal()
    static let renderer = Renderer(config: config, terminal: terminal)

    static func main() async {
        terminal.setupRawMode(title: config.appName)
        await renderer.setupScreen()
        await renderer.showWelcome()
        await renderer.renderFooter()

        // Handle input and stream backend events here.
        // See Example/Sources/ExampleApp.swift for a complete loop.

        terminal.restoreMode()
    }
}
```

## Backend Integration Model

SwiftCoderTUI intentionally does not define your LLM transport protocol. A typical pattern is:

1. Define your own stream event enum.
2. Convert backend tokens/events into renderer calls.
3. Keep rendering and business logic separated.

Example event shape used in this repository:

```swift
public enum StreamEvent {
    case thinking(String)
    case toolCall(name: String, args: String, needsApproval: Bool)
    case toolOutput(String)
    case word(String)
    case stats(tokens: Int, tps: Double, elapsed: TimeInterval)
    case done(cancelled: Bool)
}
```

Typical render loop mapping:

```swift
for await event in stream {
    switch event {
    case .thinking(let note):
        await renderer.setThinking(note)
    case .toolCall(let name, let args, let needsApproval):
        await renderer.requestApproval(tool: name, args: args)
        // your approve/reject handling
    case .toolOutput(let output):
        await renderer.printScrollLine(output)
    case .word(let token):
        await renderer.appendStreamWord(token)
    case .stats:
        await renderer.flushStreamLine()
    case .done:
        await renderer.setGenerating(false)
        await renderer.renderFooter()
    }
}
```

## Autocomplete

Use the built-in AppConfig slash command completion or plug in your own provider.

```swift
struct HelpCommand: SlashCommand {
    let name = "help"
    let description: String? = "Show help"
    func argumentCompletions(prefix: String) -> [AutocompleteItem] { [] }
}

let provider = CombinedAutocompleteProvider(commands: [HelpCommand()])
await renderer.setAutocompleteProvider(provider)
```

This supports command and argument completion, plus file-oriented completion strategies through provider hooks.

## Markdown and Diff Rendering

- MarkdownRenderer renders markdown to ANSI-styled terminal text.
- StreamFormatter styles streamed fenced code blocks and diff lines.
- DiffRenderer supports minimal update rendering for viewport-style apps built on FrameBuffer.

## Core API Snapshot

Renderer is an actor and should be awaited.

- Screen/lifecycle:
  - setupScreen()
  - showWelcome()
  - renderFooter()
  - updateSize()
  - handleResize(oldRows:oldCols:)
- Input:
  - appendChar(_)
  - deleteChar()
  - submitInput()
  - setInputBuffer(_)
  - moveCursorLeft()/moveCursorRight()
  - moveCursorToStart()/moveCursorToEnd()
- Streaming:
  - setGenerating(_)
  - appendStreamWord(_)
  - flushStreamLine()
  - advanceSpinner()
  - renderSpinnerTick()
- Session/content:
  - addHistoryEntry(_)
  - printScrollLine(_)
  - printScrollLines(_)
  - clearConversation()
- Autocomplete:
  - setAutocompleteProvider(_)
  - isAutocompleteActive()
  - moveAutocompleteSelection(offset:)
  - acceptAutocomplete()
- Approval:
  - requestApproval(tool:args:isPlanMode:)
  - moveApprovalSelection(offset:)
  - clearApproval()

## Keyboard UX

Default UX includes:

- Enter to submit.
- Shift+Enter, Alt+Enter, and Ctrl+J newline pathways.
- Ctrl+A/E/U/K/W editing shortcuts.
- Ctrl+P and Shift+Ctrl+P model cycling.
- Shift+Tab mode cycling.
- Esc cancellation.
- Ctrl+V voice input (if a provider is configured).
- Bracketed paste handling.

## Run the Example

```bash
swift run Example
```

The Example target demonstrates:

- AppConfig customization.
- Full input loop with key handling.
- Mock streaming response integration.
- Tool call + approval flows.
- Slash-command command handlers and autocomplete.
- Footer/status and resize behavior.

## Development

```bash
swift build
swift test
```

Recommended local workflow:

1. Run tests after each renderer/input/autocomplete change.
2. Use VirtualTerminal-based tests when adjusting ANSI/layout behavior.
3. Verify terminal interactions manually with the Example target.

## Testing Scope

Current tests cover:

- ANSI wrapping and visible width behavior.
- Frame buffer and differential rendering.
- Markdown and stream formatting.
- Footer/layout/resize edge cases.
- Color and box-style helpers.
- Virtual terminal behavior.
- Renderer model command and command palette behavior.

## Example Commands and Helpers

The repository includes sample command parsers and helpers you can adapt:

- model selection command parsing.
- caffeinate command/state integration.
- bash execution integration hooks.

## Contributing

Contributions are welcome.

When proposing changes:

- Keep terminal behavior deterministic and test-covered.
- Preserve renderer actor isolation and public API compatibility.
- Add or update tests for any ANSI/layout/rendering behavior changes.

## Acknowledgments

- Inspired by modern coder TUIs and terminal-first AI workflows.
- Uses apple/swift-markdown for markdown parsing and AST traversal.

## License

MIT. See [LICENSE](LICENSE).
