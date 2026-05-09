# SwiftCoderTUI — Coding Agent Guide

SwiftCoderTUI is a Swift library for building full-screen, terminal-based AI coding
assistants. It provides a ready-made TUI shell — scroll area, footer with status bar,
spinner, autocomplete, approval dialogs — that you wire up to any LLM backend.

**Your job as a coding agent** is to supply `AppConfig` (name, version, models, modes,
slash-commands) and a streaming backend. The library renders everything else.

---

## Quick-start checklist

1. Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/eduardogoncalves/swift-coder-tui", from: "1.0.0")
```

2. Add `"SwiftCoderTUI"` to your target's dependencies.

3. Create an `AppConfig`, a `Renderer`, and an `@main` entry struct.

4. Implement (or reuse) a streaming function that returns `AsyncStream<StreamEvent>`.

5. Run `swift build` and test in your terminal.

---

## AppConfig — what the agent must fill in

`AppConfig` is the **only** place that encodes the identity of your tool.
None of these values are hard-coded in the library.

```swift
import SwiftCoderTUI

let config = AppConfig(
    appName:        "MyTool",       // shown in window title and welcome banner
    version:        "1.0.0",        // shown next to the app name on startup
    welcomeMessage: "type a prompt and press Enter",

    // Models the user cycles through with Ctrl+P
    models: [
        AppConfig.ModelConfig(id: "apex-ultra",  label: "apex-ultra"),
        AppConfig.ModelConfig(id: "nova-coder",  label: "nova-coder"),
    ],

    // Thinking modes the user cycles through with Shift+Tab.
    // The convention used in the Example app is off/minimal/low/medium/high.
    // barColor:   ANSI color for the separator bars in the content area
    // badgeColor: ANSI color for the [thinking: x] badge in the status bar
    modes: [
        AppConfig.ModeConfig(id: "off",     label: "off",
                             barColor:   "\u{001B}[90m",
                             badgeColor: "\u{001B}[90m"),
        AppConfig.ModeConfig(id: "minimal", label: "minimal",
                             barColor:   "\u{001B}[34m",
                             badgeColor: "\u{001B}[34m"),
        AppConfig.ModeConfig(id: "low",     label: "low",
                             barColor:   "\u{001B}[96m",
                             badgeColor: "\u{001B}[96m"),
        AppConfig.ModeConfig(id: "medium",  label: "medium",
                             barColor:   "\u{001B}[33m",
                             badgeColor: "\u{001B}[93m"),
        AppConfig.ModeConfig(id: "high",    label: "high",
                             barColor:   "\u{001B}[35m",
                             badgeColor: "\u{001B}[95m"),
    ],

    // Slash-commands surfaced in autocomplete when the user types "/"
    commands: [
        AppConfig.CommandConfig(name: "/clear",    description: "Clear the conversation"),
        AppConfig.CommandConfig(name: "/exit",     description: "Quit"),
        AppConfig.CommandConfig(name: "/followup", description: "Queue a follow-up prompt"),
        AppConfig.CommandConfig(name: "/help",     description: "Show help and shortcuts"),
        AppConfig.CommandConfig(name: "/retry",    description: "Re-run last prompt"),
        AppConfig.CommandConfig(name: "/status",   description: "Show session status"),
    ],

    // Optional: override default keyboard shortcuts shown in "?" help overlay
    // keyboardShortcuts: AppConfig.defaultShortcuts,

    defaultModelIndex: 0,  // index into models array
    defaultModeIndex:  1   // index into modes array (1 = minimal)
)
```

### ANSI color reference for barColor / badgeColor

| Color          | ANSI code        |
|----------------|------------------|
| Dark gray      | `"\u{001B}[90m"` |
| Blue           | `"\u{001B}[34m"` |
| Bright cyan    | `"\u{001B}[96m"` |
| Yellow         | `"\u{001B}[33m"` |
| Bright yellow  | `"\u{001B}[93m"` |
| Magenta        | `"\u{001B}[35m"` |
| Bright magenta | `"\u{001B}[95m"` |
| Red            | `"\u{001B}[31m"` |
| Bright red     | `"\u{001B}[91m"` |
| Dim            | `"\u{001B}[2m"`  |

---

## StreamEvent — what your LLM integration must yield

Your streaming function returns `AsyncStream<StreamEvent>`. Yield these cases in order:

```
.thinking(String)                            // optional: show a thinking annotation
.toolCall(name:, args:, needsApproval:)      // optional: show a tool-call entry
.toolOutput(String)                          // optional: follow-up output from the tool
.word(String)                                // one word (or word fragment) at a time
.stats(tokens:, tps:, elapsed:)             // final stats line
.done(cancelled: Bool)                       // always last
```

Example producer skeleton:

```swift
func stream(for prompt: String) -> AsyncStream<StreamEvent> {
    AsyncStream { continuation in
        let task = Task {
            continuation.yield(.thinking("Planning the response..."))
            try? await Task.sleep(nanoseconds: 400_000_000)

            // … call your LLM API, then stream tokens:
            for token in tokens {
                guard !Task.isCancelled else {
                    continuation.yield(.done(cancelled: true))
                    continuation.finish()
                    return
                }
                continuation.yield(.word(token))
            }

            continuation.yield(.stats(tokens: count, tps: rate, elapsed: seconds))
            continuation.yield(.done(cancelled: false))
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

---

## Code-fence formatting during streaming

`StreamFormatter` is applied automatically inside `Renderer.appendStreamWord`. You do
**not** need to call it yourself — just stream tokens normally.

When the response contains markdown code fences (` ``` `) they are rendered with
structured box headers and colored content:

```
  ╭── swift ──────────────────
  │  func hello() -> String {
  │      return "world"
  │  }
  ╰───────────────────────────
```

Diff blocks (` ```diff `) additionally color `+` lines green and `-` lines red.

`StreamFormatter` resets automatically when `setGenerating(false)` is called, so fence
state never bleeds between conversations.

---

## Renderer — key API

`Renderer` is a Swift `actor`. All calls must be `await`ed.

### Screen & layout

| Call | Purpose |
|------|---------|
| `Renderer(config:terminal:)` | Create with your AppConfig and a `ProcessTerminal()` |
| `setupScreen()` | Clear screen and initial draw |
| `showWelcome()` | Print banner from config.appName + version |
| `renderFooter()` | Redraw footer (call after most keystrokes) |
| `updateSize()` | Handle SIGWINCH resize (returns old dimensions) |
| `handleResize(oldRows:oldCols:)` | Redraw after resize |
| `currentCols()` | Terminal column count |

### Content area

| Call | Purpose |
|------|---------|
| `printScrollLine(_ text:)` | Append one line to the scroll area and redraw |
| `printScrollLines(_ lines:)` | Append many lines in one batch (single redraw — prefer this for bash/tool output) |
| `clearConversation()` | Clear all content lines and history, reset scroll |
| `scroll(offset:)` | Scroll by N lines (positive = up) |
| `scrollToBottom()` | Jump to latest content |

### Streaming

| Call | Purpose |
|------|---------|
| `appendStreamWord(_ word:)` | Append one streaming token (auto-wraps; formats code fences) |
| `flushStreamLine()` | Commit any partial line after streaming ends |
| `setGenerating(_ flag:)` | Show/hide spinner; resets StreamFormatter on `false` |
| `advanceSpinner()` | Tick spinner frame (call every 100 ms in a Task loop) |
| `renderSpinnerTick()` | Redraw footer with latest spinner frame |
| `setThinking(_ note:)` | Update the thinking annotation next to spinner |

### Input editing

| Call | Purpose |
|------|---------|
| `appendChar(_ ch:)` | Append a character at cursor |
| `deleteChar()` | Delete character before cursor |
| `moveCursorLeft()` / `moveCursorRight()` | Move cursor one character |
| `moveCursorToStart()` | Ctrl+A — cursor to start of input |
| `moveCursorToEnd()` | Ctrl+E — cursor to end of input |
| `clearLineAfterCursor()` | Ctrl+K — delete from cursor to end |
| `clearLineBeforeCursor()` | Ctrl+U — delete from start to cursor |
| `deleteWordBefore()` | Ctrl+W — delete word before cursor |
| `insertText(_ text:)` | Insert multi-character string (e.g. from paste event) |
| `getInputBuffer()` | Return the current input string |
| `setInputBuffer(_ text:)` | Replace input (use for history navigation) |
| `submitInput()` | Return trimmed input and clear the buffer |
| `getCursorPos()` | Cursor offset into input buffer |
| `convertBackslashToNewline()` | Convert trailing `\` to newline; returns `true` if applied |

### History & session

| Call | Purpose |
|------|---------|
| `addHistoryEntry(_ entry:)` | Push a `SessionEntry` to session history |
| `getCurrentModeBadgeColor()` | ANSI string for the active mode (use in `.thinking`) |
| `getCurrentModelLabel()` | Label of the active model |
| `getCurrentModeLabel()` | Label of the active thinking mode |
| `getHistoryCount()` | Number of session history entries |
| `getIsGenerating()` | Whether generation is active |

### Autocomplete

| Call | Purpose |
|------|---------|
| `setAutocompleteProvider(_ provider:)` | Replace built-in autocomplete with a custom provider (`nil` reverts to AppConfig) |
| `isAutocompleteActive()` | Whether the autocomplete popup is open |
| `moveAutocompleteSelection(offset:)` | Move selection up/down |
| `acceptAutocomplete()` | Apply the selected suggestion |
| `clearAutocomplete()` | Dismiss without applying |
| `getSelectedAutocompleteCommand()` | Current selection as a String (AppConfig mode only) |

### Approval dialog

| Call | Purpose |
|------|---------|
| `requestApproval(tool:args:options:)` | Show a modal approval dialog |
| `clearApproval()` | Dismiss the approval dialog |
| `moveApprovalSelection(offset:)` | Move between dialog options |
| `getApprovalSelection()` | Currently selected option index |

### Model / mode cycling

| Call | Purpose |
|------|---------|
| `cycleMode()` / `cycleModel()` | Cycle forward through modes / models |
| `cycleModel(reverse:)` | Cycle backward when `reverse: true` |
| `setPendingCount(_ n:)` | Update the queued-prompt badge |
| `setAutopilot(_ enabled:)` | Enable/disable autopilot indicator |
| `isAutopilotEnabled()` | Current autopilot state |

---

## SessionEntry — rendering chat history

`SessionEntry` produces styled ANSI strings for display. Pass them to
`printScrollLine(_:)` or `addHistoryEntry(_:)`.

```swift
// User turn
let user = SessionEntry(role: .user, content: prompt)
await renderer.addHistoryEntry(user)
await renderer.printScrollLine(user.render())

// Thinking annotation
let badgeColor = await renderer.getCurrentModeBadgeColor()
let thinking = SessionEntry(role: .thinking(badgeColor: badgeColor), content: "Analyzing…")
await renderer.printScrollLine(thinking.render())

// Tool call (renders as a fenced box)
let call = SessionEntry(role: .toolCall, content: "read_file\npath: main.swift")
await renderer.printScrollLine(call.render())

// Tool output (renders as a fenced box, multi-line content split by \n)
let out = SessionEntry(role: .toolOutput, content: "file1.swift\nfile2.swift")
await renderer.printScrollLine(out.render())

// Stats after streaming ends
let stats = SessionEntry(role: .stats, content: "",
                         tokenCount: 320, tokensPerSecond: 42.5, elapsed: 7.5)
await renderer.printScrollLine(stats.render())
```

### Tool call fenced-box format

```
  ╭── 🔨 bash ─────────────────
  │  command: swift build
  ╰─────────────────────────────
```

### Tool output fenced-box format

```
  ╭── output ───────────────────
  │ Build complete!
  ╰─────────────────────────────
```

For bash `!`/`!!` commands use the same box style with the command as the label
(see `Example/Sources/ExampleApp.swift` for the reference implementation).

---

## InputHistory — command-history navigation

`InputHistory` stores submitted prompts and provides Up/Down navigation like a shell.

```swift
let history = InputHistory(capacity: 1000)  // default 1000 entries

// On submit
history.add(prompt)
history.resetCursor()

// On arrowUp (when autocomplete is closed)
if let prev = history.previous() {
    await renderer.setInputBuffer(prev)
}

// On arrowDown
if let next = history.next() {
    await renderer.setInputBuffer(next)
} else {
    await renderer.setInputBuffer("")  // clear back to draft
}
```

Key properties:
- Consecutive duplicates are deduplicated automatically.
- `previous()` clamps at the oldest entry (never returns `nil` when history is non-empty).
- `next()` returns `nil` when past the newest entry (signal to restore the live draft).
- `search(prefix:)` returns all entries matching a prefix — useful for Ctrl+R search.

---

## BashExecutor — running shell commands

> **Note:** Commands are passed directly to `/bin/zsh -c`, so shell metacharacters
> (`|`, `;`, `&&`, `$()`, etc.) are interpreted normally. The `!`/`!!` handlers in the
> Example app are intentionally unrestricted — they are explicit shell-execution
> features for a local TUI where the user is already operating their own terminal.

```swift
let executor = BashExecutor()

// Basic run (waits for process exit)
let result = try await executor.run("swift build")
print(result.output)    // combined stdout+stderr
print(result.exitCode)  // Int

// Cap output to N lines (process is terminated after the Nth line arrives)
let result = try await executor.run("find . -name '*.swift'", lineLimit: 10)
if result.truncated {
    // Output was cut off; inform the user
}
```

`BashResult` fields:

| Field | Type | Description |
|-------|------|-------------|
| `output` | `String` | Combined stdout + stderr |
| `exitCode` | `Int` | Process exit code |
| `truncated` | `Bool` | `true` when `lineLimit` caused early termination |

Display pattern used in the Example app:

```swift
let gray = DesignSystem.darkGray; let rst = DesignSystem.reset
await renderer.printScrollLine("\(gray)  ╭── \(rst)\(DesignSystem.brightYellow)! \(cmd)\(rst)")
let result = try? await bashExecutor.run(String(cmd), lineLimit: 10)
if let result {
    if !result.output.isEmpty {
        let formatted = result.output.components(separatedBy: "\n")
            .map { "\(gray)  │ \(rst)\(DesignSystem.Tool.output)\($0)\(rst)" }
        await renderer.printScrollLines(formatted)
    }
    if result.truncated {
        await renderer.printScrollLine("\(gray)  │ \(rst)\(DesignSystem.dim)… output truncated\(rst)")
    }
    if result.exitCode != 0 && !result.truncated {
        await renderer.printScrollLine("\(gray)  │ \(rst)\(DesignSystem.Status.error)exit \(result.exitCode)\(rst)")
    }
}
await renderer.printScrollLine("\(gray)  ╰────────────────────────────\(rst)")
```

---

## AutocompleteProvider — custom completions

By default the autocomplete popup shows slash-commands from `AppConfig`.  
Call `renderer.setAutocompleteProvider(_:)` once at startup to replace it with
richer, pluggable completions.

### CombinedAutocompleteProvider

The ready-to-use implementation combines slash-command, file-path, and `@mention`
completion — drop it in when building a coding-assistant:

```swift
import SwiftCoderTUI

// Convert AppConfig commands to AutocompleteItems (value = name without leading "/")
let staticItems = config.commands.map {
    AutocompleteItem(value: String($0.name.dropFirst()),
                     label: $0.name,
                     description: $0.description)
}

let provider = CombinedAutocompleteProvider(
    staticCommands: staticItems,          // slash-command pop-up items
    basePath: FileManager.default.currentDirectoryPath  // root for path completion
)
await renderer.setAutocompleteProvider(provider)
```

**What it does:**

| User types | Popup shows |
|-----------|-------------|
| `/cl` | `/clear`, `/close`, … |
| `~/Proj` | Files under `~/Projects/` |
| `@src/` | Attachable files under `src/` |
| `./Tests/` | Files under `./Tests/` |

Pass `nil` to `setAutocompleteProvider(_:)` to revert to the AppConfig default.

### Custom AutocompleteProvider

Implement the `AutocompleteProvider` protocol for fully custom completions (AI model
names, git branches, remote resources, etc.):

```swift
struct ModelAutocomplete: AutocompleteProvider {
    let models = ["apex-ultra", "apex-swift", "nova-coder"]

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int)
        -> AutocompleteSuggestion?
    {
        let line = lines[safe: cursorLine] ?? ""
        let col  = min(cursorCol, line.count)
        let text = String(line.prefix(col))

        guard text.hasPrefix("@model:") else { return nil }
        let typed = String(text.dropFirst(7))
        let items = models
            .filter { $0.lowercased().hasPrefix(typed.lowercased()) }
            .map { AutocompleteItem(value: $0, label: $0) }
        return items.isEmpty ? nil : AutocompleteSuggestion(items: items, prefix: text)
    }
}

await renderer.setAutocompleteProvider(ModelAutocomplete())
```

`applyCompletion` has a sensible default: it replaces the `prefix.count` characters
immediately before the cursor with the accepted `item.value`.  Override it when you
need non-trivial cursor placement (e.g. multi-line templates).

---

## TruncatedText — ANSI-safe truncation

Use `TruncatedText` when rendering text that must fit in a fixed column width and may
contain ANSI escape sequences (which add invisible bytes that throw off `count`):

```swift
// Truncate a styled string to 40 visible columns
let fitted = TruncatedText.truncate(styledLabel, toWidth: 40)

// Render a label inside a padded cell of a given width
let cell = TruncatedText.render(styledLabel, width: cols - 4, paddingX: 2)
```

`truncate(_:toWidth:ellipsis:)` — clips to `toWidth` visible characters and appends
`ellipsis` (default `"…"`) when the text is too long.

`render(_:width:paddingX:)` — adds `paddingX` spaces on each side, clips if still
too long, and pads with trailing spaces to fill `width` exactly.

---

```swift
DesignSystem.brightYellow   // headings / user labels
DesignSystem.brightCyan     // accent text
DesignSystem.darkGray       // secondary / dim info
DesignSystem.Status.info    // informational message
DesignSystem.Status.success // success / confirmation
DesignSystem.Status.warning // warning
DesignSystem.Status.error   // error
DesignSystem.Tool.call      // tool-call highlight
DesignSystem.Tool.output    // tool-output text
DesignSystem.bold           // bold text
DesignSystem.dim            // dim text
DesignSystem.reset          // reset all attributes
```

---

## Full entry-point skeleton (@main)

```swift
import SwiftCoderTUI

@main
struct MyApp {
    static let config   = AppConfig( /* … fill in … */ )
    static let terminal = ProcessTerminal()
    static let renderer = Renderer(config: config, terminal: terminal)
    static var activeTask:    Task<Void, Never>? = nil
    static var spinnerTask:   Task<Void, Never>? = nil
    static var pendingPrompts: [String] = []
    static let bashExecutor   = BashExecutor()
    static let inputHistory   = InputHistory()
    static var lastPrompt:    String? = nil
    static var approvalContinuation: CheckedContinuation<Int?, Never>? = nil

    static func startStreaming(prompt: String) async {
        lastPrompt = prompt
        await renderer.setGenerating(true)
        await renderer.renderFooter()

        let badgeColor = await renderer.getCurrentModeBadgeColor()
        let userEntry = SessionEntry(role: .user, content: prompt)
        await renderer.addHistoryEntry(userEntry)
        await renderer.printScrollLine(userEntry.render())

        spinnerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await renderer.advanceSpinner()
                await renderer.renderSpinnerTick()
            }
        }

        for await event in myLLMStream(for: prompt) {
            switch event {
            case .thinking(let note):
                let e = SessionEntry(role: .thinking(badgeColor: badgeColor), content: note)
                await renderer.printScrollLine(e.render())
                await renderer.setThinking(note)
            case .word(let w):
                await renderer.appendStreamWord(w)
            case .toolCall(let name, let args, _):
                let e = SessionEntry(role: .toolCall, content: "\(name)\n\(args)")
                await renderer.printScrollLine(e.render())
            case .toolOutput(let o):
                await renderer.printScrollLine(
                    SessionEntry(role: .toolOutput, content: o).render())
            case .stats(let t, let tps, let e):
                await renderer.flushStreamLine()
                await renderer.printScrollLine(
                    SessionEntry(role: .stats, content: "",
                                 tokenCount: t, tokensPerSecond: tps, elapsed: e).render())
            case .done:
                break
            }
        }

        spinnerTask?.cancel()
        await renderer.setGenerating(false)
        await renderer.renderFooter()
    }

    static func main() async {
        terminal.setupRawMode(title: config.appName)
        signal(SIGWINCH) { _ in
            Task {
                let old = await renderer.updateSize()
                await renderer.handleResize(oldRows: old.oldRows, oldCols: old.oldCols)
            }
        }

        await renderer.setupScreen()
        await renderer.showWelcome()
        await renderer.renderFooter()

        for await key in InputHandler.keystrokes() {
            switch key {
            case .character(let ch):
                await renderer.appendChar(ch)
                await renderer.scrollToBottom()
            case .delete:
                await renderer.deleteChar()
                await renderer.renderFooter()
            case .enter:
                if let prompt = await renderer.submitInput() {
                    inputHistory.add(prompt)
                    inputHistory.resetCursor()
                    activeTask = Task { await startStreaming(prompt: prompt) }
                }
            case .arrowUp:
                if await renderer.isAutocompleteActive() {
                    await renderer.moveAutocompleteSelection(offset: -1)
                } else if let prev = inputHistory.previous() {
                    await renderer.setInputBuffer(prev)
                } else {
                    await renderer.scroll(offset: 1)
                }
            case .arrowDown:
                if await renderer.isAutocompleteActive() {
                    await renderer.moveAutocompleteSelection(offset: 1)
                } else if let next = inputHistory.next() {
                    await renderer.setInputBuffer(next)
                } else {
                    await renderer.setInputBuffer("")
                }
            case .ctrlA: await renderer.moveCursorToStart(); await renderer.renderFooter()
            case .ctrlE: await renderer.moveCursorToEnd(); await renderer.renderFooter()
            case .ctrlU: await renderer.clearLineBeforeCursor(); await renderer.renderFooter()
            case .ctrlK: await renderer.clearLineAfterCursor(); await renderer.renderFooter()
            case .ctrlW: await renderer.deleteWordBefore(); await renderer.renderFooter()
            case .ctrlL: await renderer.clearConversation(); await renderer.renderFooter()
            case .paste(let text): await renderer.insertText(text); await renderer.renderFooter()
            case .ctrlC:
                terminal.restoreMode()
                exit(0)
            default:
                break
            }
        }
    }
}
```

For a complete, runnable event loop (autocomplete, approval, scroll, bash commands,
multi-line input, queued prompts, `/clear`, `/retry`, `/status`, `/help`) see
`Example/Sources/ExampleApp.swift`.

---

## File structure reference

```
Sources/SwiftCoderTUI/
├── AppConfig.swift               ← define your app identity here
├── Renderer.swift                ← actor: layout, drawing, state, input editing
├── AutocompleteProvider.swift    ← AutocompleteProvider protocol + AutocompleteItem
├── CombinedAutocompleteProvider.swift  ← slash-command + file-path + @mention completion
├── TruncatedText.swift           ← ANSI-aware fixed-width text truncation
├── SessionModel.swift            ← SessionEntry and its Role enum
├── StreamFormatter.swift         ← stateful code-fence formatter (auto-applied in streaming)
├── DesignSystem.swift            ← ANSI color constants
├── Terminal.swift                ← raw-mode helpers and ANSI utilities
├── InputHandler.swift            ← async keystroke reader (AsyncStream<Keystroke>)
├── InputHistory.swift            ← command-history store with Up/Down navigation
├── BashExecutor.swift            ← run shell commands, capture output, cap output lines
└── MockData.swift                ← mock streaming data (for demos and tests)

Example/Sources/
├── ExampleApp.swift       ← full reference implementation (@main entry point)
└── MockData.swift         ← mock streaming data wired to StreamEvent
```
