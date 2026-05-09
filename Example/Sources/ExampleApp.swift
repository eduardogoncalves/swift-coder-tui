#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import SwiftCoderTUI

// MARK: - Main Entry Point

@main
@MainActor
struct ExampleApp {
    // MARK: - App Configuration
    //
    // This is the section a coding agent should customise. Change appName, version,
    // models, modes, and commands to match the tool being built.
    static let appConfig = AppConfig(
        appName: "MyCodeAssistant",
        version: "1.0.0",
        welcomeMessage: "type a prompt and press Enter · type ? for keyboard shortcuts",
        models: [
            AppConfig.ModelConfig(id: "apex-ultra",        label: "apex-ultra"),
            AppConfig.ModelConfig(id: "apex-swift",        label: "apex-swift"),
            AppConfig.ModelConfig(id: "nova-coder",        label: "nova-coder"),
            AppConfig.ModelConfig(id: "prism-flash",       label: "prism-flash"),
        ],
        modes: [
            AppConfig.ModeConfig(id: "off",     label: "off",
                                 barColor: "\u{001B}[90m", badgeColor: "\u{001B}[90m"),
            AppConfig.ModeConfig(id: "minimal", label: "minimal",
                                 barColor: "\u{001B}[34m", badgeColor: "\u{001B}[34m"),
            AppConfig.ModeConfig(id: "low",     label: "low",
                                 barColor: "\u{001B}[96m", badgeColor: "\u{001B}[96m"),
            AppConfig.ModeConfig(id: "medium",  label: "medium",
                                 barColor: "\u{001B}[33m", badgeColor: "\u{001B}[93m"),
            AppConfig.ModeConfig(id: "high",    label: "high",
                                 barColor: "\u{001B}[35m", badgeColor: "\u{001B}[95m"),
        ],
        commands: [
            AppConfig.CommandConfig(name: "/caffeinate", description: "Manage keep-alive mode (prevents system sleep)"),
            AppConfig.CommandConfig(name: "/clear",      description: "Clear the conversation"),
            AppConfig.CommandConfig(name: "/followup",   description: "Queue a follow-up prompt"),
            AppConfig.CommandConfig(name: "/help",       description: "Show help and shortcuts"),
            AppConfig.CommandConfig(name: "/model",      description: "Switch the active model"),
            AppConfig.CommandConfig(name: "/mode",       description: "Switch thinking mode (off/minimal/low/medium/high)"),
            AppConfig.CommandConfig(name: "/quit",       description: "Quit the application"),
            AppConfig.CommandConfig(name: "/demo",       description: "Simulate a full coding assistant session"),
            AppConfig.CommandConfig(name: "/retry",      description: "Re-run the last prompt"),
            AppConfig.CommandConfig(name: "/status",     description: "Show session status"),
        ],
        defaultModelIndex: 0,
        defaultModeIndex: 1
    )
    static let processTerminal = ProcessTerminal()
    static let renderer = Renderer(config: appConfig, terminal: processTerminal)
    static var activeStreamTask: Task<Void, Never>? = nil
    static var spinnerTask: Task<Void, Never>? = nil
    static var pendingPrompts: [String] = []
    static let bashExecutor = BashExecutor()
    static let inputHistory = InputHistory()
    static var draftInput: String? = nil   // saved when entering history navigation
    static var lastPrompt: String? = nil
    static let caffeinateManager = CaffeinateManager()

    static var approvalContinuation: CheckedContinuation<Int?, Never>? = nil
    static var sigwinchSource: DispatchSourceSignal?
    static var pendingResizeTask: Task<Void, Never>?

    /// Number of output lines shown in the TUI preview for `!` and `!!` commands.
    /// The process is never killed early — the full output is always captured;
    /// only the rendered preview is capped at this count.
    static let shellPreviewLineLimit = 20

    // MARK: - Signal Handler for SIGWINCH

    static func installSigwinchHandler() {
        signal(SIGWINCH, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        source.setEventHandler {
            // Coalesce rapid resize bursts; render once for the final size.
            pendingResizeTask?.cancel()
            pendingResizeTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard !Task.isCancelled else { return }
                let old = await renderer.updateSize()
                await renderer.handleResize(oldRows: old.oldRows, oldCols: old.oldCols)
            }
        }
        source.resume()
        sigwinchSource = source
    }

    // MARK: - Streaming Response

    static func startStreaming(prompt: String) async {
        lastPrompt = prompt
        await renderer.setGenerating(true)
        await renderer.setActiveFile(nil)
        await renderer.renderFooter()

        let userEntry = SessionEntry(role: .user, content: prompt)
        await renderer.addHistoryEntry(userEntry)
        await renderer.printScrollLine(userEntry.render())

        let badgeColor = await renderer.getCurrentModeBadgeColor()

        // Spinner
        spinnerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                await renderer.advanceSpinner()
                await renderer.renderSpinnerTick()
            }
        }

        // Stream from MockData (replace with real LLM call in production)
        let stream = MockData.stream(for: prompt)

        for await event in stream {
            switch event {
            case .thinking(let note):
                let entry = SessionEntry(role: .thinking(badgeColor: badgeColor), content: note)
                await renderer.addHistoryEntry(entry)
                await renderer.printScrollLine(entry.render())
                await renderer.setThinking(note)

            case .toolCall(let name, let args, let needsApproval):
                let callContent = "\(name) \(args)"
                let entry = SessionEntry(role: .toolCall, content: callContent)
                await renderer.addHistoryEntry(entry)
                await renderer.printScrollLine(entry.render())

                let fileExtensions = [".swift", ".py", ".js", ".ts", ".go", ".rs",
                                      ".c", ".cpp", ".java", ".md", ".json", ".yaml", ".txt"]
                let argWords = args.split(separator: " ").map(String.init)
                if let filePath = argWords.first(where: { w in
                    fileExtensions.contains(where: { w.hasSuffix($0) })
                }) {
                    await renderer.setActiveFile(filePath)
                }

                let autopilot = await renderer.isAutopilotEnabled()
                if needsApproval && !autopilot {
                    await renderer.requestApproval(tool: name, args: args)
                    let choice = await withCheckedContinuation { cont in
                        approvalContinuation = cont
                    }
                    await renderer.clearApproval()

                    if choice == nil || choice == 3 {
                        await renderer.printScrollLine("\(DesignSystem.red)Tool call rejected.\(DesignSystem.reset)")
                        cancelStreaming()
                        return
                    }
                    if choice == 2 {
                        await renderer.setAutopilot(true)
                    }
                }

            case .toolOutput(let output):
                let entry = SessionEntry(role: .toolOutput, content: output)
                await renderer.addHistoryEntry(entry)
                await renderer.printScrollLine(entry.render())

            case .word(let word):
                await renderer.appendStreamWord(word)

            case .stats(let tokens, let tps, let elapsed):
                await renderer.flushStreamLine()
                let statsEntry = SessionEntry(role: .stats, content: "",
                                              tokenCount: tokens,
                                              tokensPerSecond: tps,
                                              elapsed: elapsed)
                await renderer.addHistoryEntry(statsEntry)
                await renderer.printScrollLine(statsEntry.render())
                await renderer.printScrollLine("")

            case .done(let cancelled):
                if cancelled { break }
            }
        }

        spinnerTask?.cancel()
        spinnerTask = nil

        if !Task.isCancelled {
            await renderer.setGenerating(false)
            await renderer.renderFooter()

            if !pendingPrompts.isEmpty {
                let next = pendingPrompts.removeFirst()
                await renderer.setPendingCount(pendingPrompts.count)
                activeStreamTask = Task { await startStreaming(prompt: next) }
            }
        }
    }

    static func cancelStreaming() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        spinnerTask?.cancel()
        spinnerTask = nil
        Task {
            await renderer.flushStreamLine()
            await renderer.printScrollLine("\(DesignSystem.red)Operation aborted.\(DesignSystem.reset)")
            await renderer.printScrollLine("")

            if !pendingPrompts.isEmpty {
                let next = pendingPrompts.removeFirst()
                await renderer.setPendingCount(pendingPrompts.count)
                activeStreamTask = Task { await startStreaming(prompt: next) }
            } else {
                await renderer.setGenerating(false)
                await renderer.renderFooter()
            }
        }
    }

    static func cleanExit() {
        activeStreamTask?.cancel()
        spinnerTask?.cancel()
        let farewells = [
            "Goodbye! Happy coding!",
            "See you next time!",
            "Farewell! May your code compile on the first try.",
            "Logging off. Until next time!",
        ]
        ExampleApp.processTerminal.restoreMode()
        ExampleApp.processTerminal.write("\r\n\(DesignSystem.brightYellow)\(farewells.randomElement()!)\(DesignSystem.reset)\r\n")
        exit(0)
    }

    // MARK: - Main

    static func main() async {
        ExampleApp.processTerminal.setupRawMode(title: appConfig.appName)
        installSigwinchHandler()

        signal(SIGINT) { _ in ExampleApp.cleanExit() }

        // Wire autocomplete: slash commands + file-path + @mention completion.
        // Commands with their own SlashCommand handler are excluded from static items.
        let dynamicCommandNames: Set<String> = ["/model", "/caffeinate"]
        let staticItems = appConfig.commands
            .filter { !dynamicCommandNames.contains($0.name) }
            .map {
                AutocompleteItem(value: String($0.name.dropFirst()), label: $0.name, description: $0.description)
            }
        let provider = CombinedAutocompleteProvider(
            commands: [ModelSlashCommand(models: appConfig.models), CaffeinateSlashCommand()],
            staticCommands: staticItems
        )
        await renderer.setAutocompleteProvider(provider)

        await renderer.setupScreen()
        await renderer.showWelcome()
        await renderer.renderFooter()

        var shouldExit = false
        mainLoop: for await key in InputHandler.keystrokes() {
            // Approval intercept
            if let continuation = approvalContinuation {
                switch key {
                case .character(let ch):
                    if let digit = Int(String(ch)), digit >= 1 && digit <= 4 {
                        approvalContinuation = nil
                        continuation.resume(returning: digit - 1)
                    }
                case .enter:
                    let selection = await renderer.getApprovalSelection()
                    approvalContinuation = nil
                    continuation.resume(returning: selection)
                case .escape:
                    approvalContinuation = nil
                    continuation.resume(returning: nil)
                case .arrowUp:
                    await renderer.moveApprovalSelection(offset: -1)
                case .arrowDown:
                    await renderer.moveApprovalSelection(offset: 1)
                default:
                    break
                }
                continue
            }

            switch key {
            case .character(let ch):
                await renderer.appendChar(ch)

            case .shiftEnter:
                await renderer.appendChar("\n")
                await renderer.renderFooter()

            case .backspace:
                await renderer.deleteChar()
                await renderer.renderFooter()

            case .arrowLeft:
                await renderer.moveCursorLeft()
                await renderer.renderFooter()

            case .arrowRight:
                await renderer.moveCursorRight()
                await renderer.renderFooter()

            case .pageUp, .mouseScrollUp, .optionUp:
                break  // terminal scrollback handles scrolling natively

            case .pageDown, .mouseScrollDown, .optionDown:
                break  // terminal scrollback handles scrolling natively

            case .enter:
                if await renderer.isAutocompleteActive() {
                    let result = await renderer.acceptAutocomplete()
                    await renderer.renderFooter()
                    // Refresh for directories (show contents) and slash commands (show argument submenu).
                    // Avoid refreshing plain file completions — the pathRegex on "file.ext " backtracks.
                    if result == .directory || result == .slashCommand {
                        Task {
                            await renderer.updateAutocomplete()
                            await renderer.renderFooter()
                        }
                    }
                    continue
                }

                if await renderer.convertBackslashToNewline() {
                    await renderer.renderFooter()
                    continue
                }

                if let prompt = await renderer.submitInput() {
                    inputHistory.add(prompt)
                    inputHistory.resetCursor()
                    draftInput = nil

                    let trimmed = prompt.trimmingCharacters(in: .whitespaces)
                    let lowercased = trimmed.lowercased()

                    if let modelIntent = ModelCommandParser.resolve(input: trimmed, models: appConfig.models) {
                        switch modelIntent {
                        case .openMenu:
                            let currentModel = await renderer.getCurrentModelLabel()
                            let items = ModelCommandParser.menuItems(
                                models: appConfig.models,
                                currentModelLabel: currentModel
                            )
                            guard !items.isEmpty else {
                                await renderer.printScrollLine(
                                    "\(DesignSystem.Status.warning)No models configured.\(DesignSystem.reset)"
                                )
                                await renderer.renderFooter()
                                continue
                            }
                            await renderer.openCommandPalette(commands: items)
                            await renderer.renderFooter()
                            continue

                        case .selectModel(let index):
                            let model = appConfig.models[index]
                            await renderer.setCurrentModelIndex(index)
                            await renderer.printScrollLine(
                                "\(DesignSystem.darkGray)Switched model to \(model.label).\(DesignSystem.reset)"
                            )
                            await renderer.renderFooter()
                            continue

                        case .invalidModelName(let name):
                            let modelList = appConfig.models.map(\.label).joined(separator: ", ")
                            await renderer.printScrollLine(
                                "\(DesignSystem.Status.warning)Unknown model '\(name)'. Available models: \(modelList)\(DesignSystem.reset)"
                            )
                            await renderer.renderFooter()
                            continue
                        }
                    }

                    if let caffIntent = CaffeinateCommandParser.resolve(input: trimmed) {
                        switch caffIntent {
                        case .openMenu:
                            let items = CaffeinateCommandParser.menuItems()
                            await renderer.openCommandPalette(commands: items)
                            await renderer.renderFooter()

                        case .on:
                            await caffeinateManager.enable(mode: .on)
                            await renderer.printScrollLine("\(DesignSystem.darkGray)Caffeinate: \(await caffeinateManager.statusDescription)\(DesignSystem.reset)")
                            await renderer.renderFooter()

                        case .busy:
                            await caffeinateManager.enable(mode: .busy)
                            await renderer.printScrollLine("\(DesignSystem.darkGray)Caffeinate: \(await caffeinateManager.statusDescription)\(DesignSystem.reset)")
                            await renderer.renderFooter()

                        case .off:
                            await caffeinateManager.disable()
                            await renderer.printScrollLine("\(DesignSystem.darkGray)Caffeinate: off\(DesignSystem.reset)")
                            await renderer.renderFooter()

                        case .duration(let seconds):
                            await caffeinateManager.enable(mode: .duration(seconds: seconds))
                            await renderer.printScrollLine("\(DesignSystem.darkGray)Caffeinate: \(await caffeinateManager.statusDescription)\(DesignSystem.reset)")
                            await renderer.renderFooter()

                        case .invalid(let arg):
                            await renderer.printScrollLine(
                                "\(DesignSystem.Status.warning)Unknown caffeinate option '\(arg)'. Usage: /caffeinate [on|off|busy|<duration>]\(DesignSystem.reset)"
                            )
                            await renderer.renderFooter()
                        }
                        continue
                    }

                    if lowercased == "/demo" {
                        await MockData.runDemo(renderer: renderer)
                        continue
                    }

                    if lowercased == "/quit" {
                        shouldExit = true
                        break mainLoop
                    }

                    if lowercased == "/clear" {
                        await renderer.clearConversation()
                        await renderer.renderFooter()
                        continue
                    }

                    if lowercased == "/retry" {
                        if let last = lastPrompt {
                            let isGen = await renderer.getIsGenerating()
                            if isGen {
                                await renderer.printScrollLine("\(DesignSystem.Status.warning)Cannot retry while generating.\(DesignSystem.reset)")
                            } else {
                                activeStreamTask = Task { await startStreaming(prompt: last) }
                            }
                        } else {
                            await renderer.printScrollLine("\(DesignSystem.dim)No previous prompt to retry.\(DesignSystem.reset)")
                        }
                        await renderer.renderFooter()
                        continue
                    }

                    if lowercased == "/status" {
                        let modelName = await renderer.getCurrentModelLabel()
                        let modeName  = await renderer.getCurrentModeLabel()
                        let msgCount  = await renderer.getHistoryCount()
                        let queueSize = pendingPrompts.count
                        let gray = DesignSystem.darkGray; let rst = DesignSystem.reset
                        let accent = DesignSystem.brightCyan
                        let sep = String(repeating: "─", count: 32)
                        await renderer.printScrollLines([
                            "\(gray)  ╭── \(rst)\(DesignSystem.bold)Session Status\(rst)",
                            "\(gray)  │ \(rst)\(accent)model    \(rst)\(modelName)",
                            "\(gray)  │ \(rst)\(accent)thinking \(rst)\(modeName)",
                            "\(gray)  │ \(rst)\(accent)messages \(rst)\(msgCount)",
                            "\(gray)  │ \(rst)\(accent)queued   \(rst)\(queueSize)",
                            "\(gray)  ╰\(sep)\(rst)",
                        ])
                        await renderer.renderFooter()
                        continue
                    }

                    if lowercased == "/help" {
                        let shortcuts = appConfig.keyboardShortcuts
                        let gray = DesignSystem.darkGray; let rst = DesignSystem.reset
                        let accent = DesignSystem.brightCyan
                        var lines: [String] = ["\(gray)  ╭── \(rst)\(DesignSystem.bold)Keyboard Shortcuts\(rst)"]
                        for s in shortcuts {
                            lines.append("\(gray)  │ \(rst)\(accent)\(s.key.padding(toLength: 32, withPad: " ", startingAt: 0))\(rst)\(s.description)")
                        }
                        let sep = String(repeating: "─", count: 32)
                        lines.append("\(gray)  ╰\(sep)\(rst)")
                        await renderer.printScrollLines(lines)
                        await renderer.renderFooter()
                        continue
                    }

                    if lowercased.hasPrefix("/followup") {
                        let message = trimmed.dropFirst("/followup".count).trimmingCharacters(in: .whitespaces)
                        guard !message.isEmpty else {
                            await renderer.printScrollLine("\(DesignSystem.Status.warning)Usage: /followup <message>\(DesignSystem.reset)")
                            await renderer.renderFooter()
                            continue
                        }
                        pendingPrompts.append(message)
                        await renderer.setPendingCount(pendingPrompts.count)
                        await renderer.printScrollLine("\(DesignSystem.darkGray)Queued follow-up [\(pendingPrompts.count)]: \(message)\(DesignSystem.reset)")
                        await renderer.renderFooter()
                        continue
                    }

                    if trimmed.hasPrefix("!!") {
                        // !! — run in shell, display output, do NOT inject into LLM.
                        let cmd = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        let gray = DesignSystem.darkGray; let rst = DesignSystem.reset
                        await renderer.printScrollLine("\(gray)  ╭── \(rst)\(DesignSystem.brightYellow)!! \(cmd)\(rst)")
                        // No lineLimit: capture the full output. Truncation is visual-only.
                        let result = try? await bashExecutor.run(String(cmd))
                        if let result {
                            if !result.output.isEmpty {
                                let allLines = result.output.components(separatedBy: "\n")
                                let previewLines = allLines.prefix(shellPreviewLineLimit)
                                let formatted = previewLines.map { "\(gray)  │ \(rst)\(DesignSystem.Tool.output)\($0)\(rst)" }
                                await renderer.printScrollLines(formatted)
                                if allLines.count > shellPreviewLineLimit {
                                    let hidden = allLines.count - shellPreviewLineLimit
                                    await renderer.printScrollLine("\(gray)  │ \(rst)\(DesignSystem.dim)… \(hidden) more line\(hidden == 1 ? "" : "s") (not shown in preview)\(rst)")
                                }
                            }
                            if result.exitCode != 0 {
                                await renderer.printScrollLine("\(gray)  │ \(rst)\(DesignSystem.Status.error)exit \(result.exitCode)\(rst)")
                            }
                        }
                        await renderer.printScrollLine("\(gray)  ╰────────────────────────────\(rst)")
                        await renderer.renderFooter()
                        continue
                    } else if trimmed.hasPrefix("!") {
                        // ! — run in shell, display preview, inject FULL output into LLM.
                        let cmd = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
                        let gray = DesignSystem.darkGray; let rst = DesignSystem.reset
                        await renderer.printScrollLine("\(gray)  ╭── \(rst)\(DesignSystem.brightYellow)! \(cmd)\(rst)")
                        // No lineLimit: capture the full output so the LLM receives all of it.
                        let result = try? await bashExecutor.run(String(cmd))
                        if let result {
                            if !result.output.isEmpty {
                                let allLines = result.output.components(separatedBy: "\n")
                                let previewLines = allLines.prefix(shellPreviewLineLimit)
                                let formatted = previewLines.map { "\(gray)  │ \(rst)\(DesignSystem.Tool.output)\($0)\(rst)" }
                                await renderer.printScrollLines(formatted)
                                if allLines.count > shellPreviewLineLimit {
                                    let hidden = allLines.count - shellPreviewLineLimit
                                    await renderer.printScrollLine("\(gray)  │ \(rst)\(DesignSystem.dim)… \(hidden) more line\(hidden == 1 ? "" : "s") (not shown in preview, full output sent to LLM)\(rst)")
                                }
                            }
                            if result.exitCode != 0 {
                                await renderer.printScrollLine("\(gray)  │ \(rst)\(DesignSystem.Status.error)exit \(result.exitCode)\(rst)")
                            }
                        }
                        await renderer.printScrollLine("\(gray)  ╰────────────────────────────\(rst)")
                        await renderer.renderFooter()
                        // Inject the full output into the LLM. Format as a shell transcript
                        // so the model has clear context of what was run and what it returned.
                        if let result, !result.output.isEmpty {
                            let llmPrompt = "$ \(cmd)\n\(result.output)"
                            activeStreamTask = Task { await startStreaming(prompt: llmPrompt) }
                        }
                        continue
                    }

                    await renderer.renderFooter()
                    let isGen = await renderer.getIsGenerating()
                    if isGen {
                        pendingPrompts.append(prompt)
                        await renderer.setPendingCount(pendingPrompts.count)
                        await renderer.renderFooter()
                    } else {
                        activeStreamTask = Task { await startStreaming(prompt: prompt) }
                    }
                }

            case .escape:
                if await renderer.isAutocompleteActive() {
                    await renderer.clearAutocomplete()
                    await renderer.renderFooter()
                    continue
                }
                let isGen = await renderer.getIsGenerating()
                if isGen {
                    cancelStreaming()
                } else {
                    let isAutopilot = await renderer.isAutopilotEnabled()
                    if isAutopilot {
                        await renderer.setAutopilot(false)
                        await renderer.printScrollLine("\(DesignSystem.yellow)Autopilot mode disabled.\(DesignSystem.reset)")
                    }
                }

            case .tab:
                if await renderer.isAutocompleteActive() {
                    let result = await renderer.acceptAutocomplete()
                    await renderer.renderFooter()
                    if result == .directory || result == .slashCommand {
                        Task {
                            await renderer.updateAutocomplete()
                            await renderer.renderFooter()
                        }
                    }
                    continue
                } else {
                    await renderer.openCommandPalette()
                }
                await renderer.renderFooter()

            case .shiftTab:
                await renderer.cycleMode()
                await renderer.renderFooter()

            case .ctrlP:
                await renderer.cycleModel()
                await renderer.renderFooter()

            case .shiftCtrlP:
                await renderer.cycleModel(reverse: true)
                await renderer.renderFooter()

            case .altEnter:
                await renderer.appendChar("\n")
                await renderer.renderFooter()

            case .ctrlC:
                shouldExit = true
                break mainLoop

            case .arrowUp:
                if await renderer.isAutocompleteActive() {
                    await renderer.moveAutocompleteSelection(offset: -1)
                } else if await renderer.isOnFirstInputLine() {
                    // Save draft the first time we enter history navigation
                    if !inputHistory.isNavigating {
                        draftInput = await renderer.getInputBuffer()
                    }
                    if let prev = inputHistory.previous() {
                        await renderer.setInputBuffer(prev)
                    }
                } else {
                    await renderer.moveCursorInInputUp()
                }

            case .arrowDown:
                if await renderer.isAutocompleteActive() {
                    await renderer.moveAutocompleteSelection(offset: 1)
                } else {
                    let onLast = await renderer.isOnLastInputLine()
                    if !onLast {
                        await renderer.moveCursorInInputDown()
                    } else if inputHistory.isNavigating {
                        if let next = inputHistory.next() {
                            await renderer.setInputBuffer(next)
                        } else {
                            // Past newest entry — restore the saved draft
                            await renderer.setInputBuffer(draftInput ?? "")
                            draftInput = nil
                            inputHistory.resetCursor()
                        }
                    }
                }

            case .ctrlA:
                await renderer.moveCursorToStart()
                await renderer.renderFooter()

            case .ctrlE:
                await renderer.moveCursorToEnd()
                await renderer.renderFooter()

            case .ctrlU:
                await renderer.clearLineBeforeCursor()
                await renderer.renderFooter()

            case .ctrlK:
                await renderer.clearLineAfterCursor()
                await renderer.renderFooter()

            case .ctrlW:
                await renderer.deleteWordBefore()
                await renderer.renderFooter()

            case .ctrlL:
                await renderer.clearConversation()
                await renderer.renderFooter()

            case .ctrlV:
                await renderer.triggerVoiceInput()

            case .paste(let text):
                await renderer.insertText(text)
                await renderer.renderFooter()

            case .delete, .unknown:
                break
            }
        }

        let wasGenerating = await renderer.getIsGenerating()
        activeStreamTask?.cancel()
        activeStreamTask = nil
        spinnerTask?.cancel()
        spinnerTask = nil
        if shouldExit && wasGenerating {
            pendingPrompts.removeAll()
            await renderer.setPendingCount(0)
            await renderer.flushStreamLine()
            await renderer.printScrollLine("\(DesignSystem.red)Operation aborted.\(DesignSystem.reset)")
            await renderer.printScrollLine("")
            await renderer.setGenerating(false)
            await renderer.renderFooter()
        } else {
            await renderer.flushStreamLine()
        }
        await renderer.teardownScreen()
        ExampleApp.processTerminal.restoreMode()
        if shouldExit {
            let farewells = [
                "Goodbye! Happy coding!",
                "See you next time!",
                "Farewell! May your code compile on the first try.",
                "Logging off. Until next time!",
            ]
            ExampleApp.processTerminal.write("\r\n\(DesignSystem.brightYellow)\(farewells.randomElement()!)\(DesignSystem.reset)\r\n")
        }
    }
}
