import Foundation

// MARK: - AutocompleteAcceptResult

/// Describes what kind of item was accepted, so callers can decide whether to
/// refresh the autocomplete popup immediately.
public enum AutocompleteAcceptResult: Sendable {
    /// A directory path was completed — refresh to show its contents.
    case directory
    /// A slash-command name was completed (buffer now ends with `/name `) —
    /// refresh to show argument completions as a submenu.
    case slashCommand
    /// An ordinary completion — no immediate refresh needed.
    case plain
}

// MARK: - Renderer

public actor Renderer {
    // App configuration (provided by the host application)
    private let config: AppConfig

    // Terminal dimensions
    private var rows: Int
    private var cols: Int

    // Input state — backed by LineEditor so editing keystrokes are O(1) on
    // String.Index instead of O(n) String.index(offsetBy:) per keystroke, and
    // word-deletion uses a Character-level walk instead of a regex compile.
    private var editor = LineEditor()
    private var inputBuffer: String { editor.text }
    private var cursorPos: Int { editor.cursorOffset }

    // Session history
    private var history: [SessionEntry] = []

    // All content lines (rendered strings for the scroll area)
    private var contentLines: [String] = []

    // Footer rendering state for the relative-cursor scrollback model
    private var renderedFooterLineCount: Int = 0
    private var renderedCursorFooterRow: Int = 0
    private var footerRenderSequence: Int = 0
    private var footerRenderTrigger: String = "init"

    // Streaming state — spinner, partial line, thinking labels, pending count.
    private var streaming = StreamingState()

    // Think-block line buffer: accumulates the current partial think line
    // between newlines. Reset at thinkingStarted/thinkingEnded.
    private var thinkLineBuffer: String = ""

    // Set by abortGeneration() to gate out any appendStreamChunk /
    // appendThinkChunk calls that arrive after an ESC-cancel.
    // Because those calls arrive through the renderer actor queue (serialized),
    // once this flag is set inside the actor any pending calls will see it.
    // Cleared when setGenerating(true) is called for the next generation.
    private var isStreamingAborted: Bool = false

    // Ephemeral one-line status notice rendered as a plain footer line
    // (no spinner glyph, no `(esc · …s)` suffix). Caller is responsible for
    // styling (ANSI escapes) and clearing via `setStatusNotice(nil)`.
    // Intended for transient UI affordances like "🎤 Listening…" that are
    // unrelated to model generation.
    private var statusNotice: String? = nil

    // Autopilot state
    private var isAutopilot: Bool = false

    // Tool-call approval prompt.
    private var approval: ApprovalState? = nil

    // Generic option picker (git setup, branch selection, etc.)
    private var optionSelect: OptionSelectState? = nil

    // Current model/mode tracked by index into config arrays
    private var currentModelIndex: Int
    private var currentModeIndex: Int
    // Overrides index-based label for synthetic/dynamic models not in config.models.
    // Cleared whenever the user cycles back to a config-indexed model.
    private var modelLabelOverride: String? = nil

    private var currentMode: AppConfig.ModeConfig { config.modes[currentModeIndex] }
    private var currentModel: AppConfig.ModelConfig { config.models[currentModelIndex] }
    private var activeModelLabel: String { modelLabelOverride ?? currentModel.label }

    // Pluggable autocomplete — when nil, falls back to AppConfig slash commands.
    private var autocompleteProvider: (any AutocompleteProvider)?

    // Autocomplete UI state — popup + ghost text + `?` help overlay.
    private var autocomplete = AutocompleteState()

    // Status bar — project breadcrumb, optional active file, git branch.
    private var statusBar = StatusBarState()

    private let terminal: any Terminal

    public init(config: AppConfig, terminal: any Terminal = ProcessTerminal()) {
        self.config            = config
        self.terminal          = terminal
        self.currentModelIndex = config.defaultModelIndex
        self.currentModeIndex  = config.defaultModeIndex
        self.rows = terminal.rows
        self.cols = terminal.cols
        self.statusBar.projectPath = FileManager.default.currentDirectoryPath
        // Branch lookup is deferred off the init thread: the `.git/HEAD` file
        // is small and usually local, but the directory may be on a slow or
        // unavailable network mount. Starting nil and resolving asynchronously
        // keeps init non-blocking and resilient.
        let cwd = self.statusBar.projectPath
        Task { [weak self] in
            let branch = StatusBarState.readGitBranch(from: cwd)
            await self?.setGitBranch(branch)
        }
    }

    private func setGitBranch(_ branch: String?) {
        statusBar.gitBranch = branch
    }

    /// Update the context-window utilisation percentage shown in the status bar.
    ///
    /// Pass `nil` to hide the badge.  Values should be in the range 0…100 (e.g. `42.3`).
    public func setContextPercent(_ percent: Double?) {
        statusBar.contextPercent = percent
    }

    /// Show or hide the Sandbox badge in the status bar.
    ///
    /// - `true`  → `[Sandbox: Enabled]`  (green)
    /// - `false` → `[Sandbox: Disabled]` (red)
    /// - `nil`   → badge is hidden
    public func setSandboxEnabled(_ enabled: Bool?) {
        statusBar.sandboxEnabled = enabled
    }

    // MARK: - Public API

    /// Update dimensions and return the old values
    public func updateSize() -> (oldRows: Int, oldCols: Int) {
        let old = (rows, cols)
        terminal.updateSize()
        rows = terminal.rows
        cols = terminal.cols
        return old
    }

    public func currentCols() -> Int { cols }

    public func getInputBuffer() -> String { inputBuffer }

    public func appendChar(_ ch: Character) {
        _ = editor.handle(key: .character(ch))
        updateAutocomplete()
    }

    public func deleteChar() {
        _ = editor.handle(key: .backspace)
        updateAutocomplete()
    }

    /// Replace the built-in AppConfig slash-command autocomplete with a custom provider.
    /// Pass `nil` to revert to the AppConfig default.
    public func setAutocompleteProvider(_ provider: (any AutocompleteProvider)?) {
        autocompleteProvider = provider
        clearAutocomplete()
    }

    public func updateAutocomplete() {
        // Help menu (always wins).
        if inputBuffer == "?" {
            autocomplete.showHelp()
            redraw()
            return
        }
        autocomplete.showHelpMenu = false

        // External AutocompleteProvider takes priority over AppConfig.
        if let provider = autocompleteProvider {
            let lines = inputBuffer
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let (cursorLine, cursorCol) = inputCursorLineAndCol()

            if let suggestion = provider.getSuggestions(
                lines: lines, cursorLine: cursorLine, cursorCol: cursorCol)
            {
                autocomplete.setExternalSuggestion(items: suggestion.items, prefix: suggestion.prefix)
            } else {
                autocomplete.clearExternal()
            }
            redraw()
            return
        }

        // --- AppConfig fallback ---
        if inputBuffer.hasPrefix("/") {
            if inputBuffer.contains(" ") {
                autocomplete.filteredCommands = []
                autocomplete.ghostSuggestion = nil
            } else {
                let commands = config.commands
                    .map { ($0.name, $0.description) }
                    .filter { $0.0.hasPrefix(inputBuffer) }
                autocomplete.setAppConfigCommands(commands)
                autocomplete.recomputeGhost(buffer: inputBuffer, hasExternalProvider: false)
            }
        } else {
            autocomplete.filteredCommands = []
            autocomplete.ghostSuggestion = nil
        }
        redraw()
    }

    /// Returns (line, col) of the cursor within the input buffer.
    private func inputCursorLineAndCol() -> (line: Int, col: Int) {
        let before = String(inputBuffer.prefix(cursorPos))
        let lines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let line = max(0, lines.count - 1)
        let col = lines.last?.count ?? 0
        return (line, col)
    }

    public func moveAutocompleteSelection(offset: Int) {
        guard autocomplete.moveSelection(offset: offset) else { return }
        autocomplete.recomputeGhost(buffer: inputBuffer, hasExternalProvider: autocompleteProvider != nil)
        redraw()
    }

    public func isAutocompleteActive() -> Bool {
        autocomplete.isActive
    }

    /// Show all slash commands in the autocomplete popup without modifying the input buffer.
    /// If an external provider is active it takes priority; otherwise shows AppConfig commands.
    public func openCommandPalette() {
        autocomplete.showHelpMenu = false
        if let provider = autocompleteProvider {
            let lines = inputBuffer
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let (cursorLine, cursorCol) = inputCursorLineAndCol()
            if let suggestion = provider.getSuggestions(
                lines: lines, cursorLine: cursorLine, cursorCol: cursorCol)
            {
                autocomplete.setExternalSuggestion(items: suggestion.items, prefix: suggestion.prefix)
            } else {
                // Fall back to all slash commands from AppConfig.
                autocomplete.filteredItems = []
                autocomplete.setAppConfigCommands(config.commands.map { ($0.name, $0.description) })
                autocomplete.externalPrefix = "/"
            }
        } else {
            autocomplete.setAppConfigCommands(config.commands.map { ($0.name, $0.description) })
        }
        redraw()
    }

    /// Show a custom command list in the autocomplete popup.
    /// This always uses AppConfig-style command selection behavior.
    public func openCommandPalette(commands: [(name: String, desc: String)]) {
        autocomplete.showHelpMenu = false
        autocomplete.clearExternal()
        autocomplete.setAppConfigCommands(commands)
        redraw()
    }

    /// Returns the full name of the selected autocomplete item (AppConfig mode only).
    /// In external-provider mode, call `acceptAutocomplete()` directly.
    public func getSelectedAutocompleteCommand() -> String? {
        autocomplete.selectedCommandName
    }

    /// Accepts the currently selected autocomplete item.
    ///
    /// Returns an ``AutocompleteAcceptResult`` that tells the caller whether to
    /// refresh the autocomplete popup:
    /// - `.directory`   — accepted a path directory; re-show contents.
    /// - `.slashCommand` — accepted a slash-command name; re-show argument completions.
    /// - `.plain`       — no refresh needed.
    @discardableResult
    public func acceptAutocomplete() -> AutocompleteAcceptResult {
        defer {
            autocomplete.reset()
            redraw()
        }

        // External provider: let it rewrite the buffer.
        if let provider = autocompleteProvider,
           autocomplete.selectedIndex < autocomplete.filteredItems.count
        {
            let item = autocomplete.filteredItems[autocomplete.selectedIndex]
            let isDirectory = item.value.hasSuffix("/")
            let lines = inputBuffer
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let (cursorLine, cursorCol) = inputCursorLineAndCol()
            let result = provider.applyCompletion(
                lines: lines, cursorLine: cursorLine, cursorCol: cursorCol,
                item: item, prefix: autocomplete.externalPrefix)
            let newBuffer = result.lines.joined(separator: "\n")
            // Move cursor to the accepted position.
            var pos = 0
            for l in 0..<result.cursorLine { pos += result.lines[l].count + 1 }
            pos += result.cursorCol
            editor.setText(newBuffer, cursorOffset: pos)
            if isDirectory { return .directory }
            if isSlashCommandJustCompleted(newBuffer, cursorPos: pos) { return .slashCommand }
            return .plain
        }

        // AppConfig palette mode — Tab inserts the selected command with a trailing space.
        if autocomplete.selectedIndex < autocomplete.filteredCommands.count {
            let newBuffer = autocomplete.filteredCommands[autocomplete.selectedIndex].name + " "
            editor.setText(newBuffer, cursorOffset: newBuffer.count)
            return .plain
        }

        // AppConfig ghost-text mode.
        if let suggestion = autocomplete.ghostSuggestion {
            let newBuffer = inputBuffer + suggestion
            editor.setText(newBuffer, cursorOffset: newBuffer.count)
        }
        return .plain
    }

    /// Returns `true` when the buffer up to `cursorPos` looks like a just-completed
    /// slash-command name: starts with `/`, contains exactly one space, and that
    /// space is the last character before the cursor (e.g. `/caffeinate |`).
    private func isSlashCommandJustCompleted(_ buffer: String, cursorPos: Int) -> Bool {
        guard buffer.hasPrefix("/") else { return false }
        let upToCursor = String(buffer.prefix(cursorPos))
        guard upToCursor.hasSuffix(" ") else { return false }
        return upToCursor.filter({ $0 == " " }).count == 1
    }

    public func clearAutocomplete() {
        autocomplete.reset()
        redraw()
    }

    public func moveCursorLeft() {
        _ = editor.handle(key: .arrowLeft)
    }

    public func moveCursorRight() {
        _ = editor.handle(key: .arrowRight)
    }

    // MARK: - Multiline cursor helpers

    /// The lines of the current input buffer.
    private func inputLines() -> [String] {
        inputBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Returns (row, col) — both 0-indexed — of the cursor within the input buffer.
    private func cursorRowAndCol() -> (row: Int, col: Int) {
        let before = String(inputBuffer.prefix(cursorPos))
        let lines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let row = max(0, lines.count - 1)
        let col = lines.last?.count ?? 0
        return (row, col)
    }

    /// True when the cursor is on the first line of the input.
    public func isOnFirstInputLine() -> Bool {
        cursorRowAndCol().row == 0
    }

    /// True when the cursor is on the last line of the input.
    public func isOnLastInputLine() -> Bool {
        let lines = inputLines()
        return cursorRowAndCol().row == max(0, lines.count - 1)
    }

    /// Move the cursor up one line within the input (same column clamped to line length).
    public func moveCursorInInputUp() {
        let lines = inputLines()
        let (row, col) = cursorRowAndCol()
        guard row > 0 else { return }
        let targetRow = row - 1
        let targetCol = min(col, lines[targetRow].count)
        let charsBeforeTarget = lines[..<targetRow].reduce(0) { $0 + $1.count + 1 }  // +1 for \n
        editor.setCursor(offset: charsBeforeTarget + targetCol)
        redraw()
    }

    /// Move the cursor down one line within the input (same column clamped to line length).
    public func moveCursorInInputDown() {
        let lines = inputLines()
        let (row, col) = cursorRowAndCol()
        guard row < lines.count - 1 else { return }
        let targetRow = row + 1
        let targetCol = min(col, lines[targetRow].count)
        let charsBeforeTarget = lines[..<targetRow].reduce(0) { $0 + $1.count + 1 }
        editor.setCursor(offset: charsBeforeTarget + targetCol)
        redraw()
    }

    /// Navigate to the previous entry in the input command history (↑ on single-line input).
    public func navigateHistoryUp() {
        _ = editor.handle(key: .arrowUp)
        updateAutocomplete()
    }

    /// Navigate to the next entry in the input command history (↓ on single-line input).
    public func navigateHistoryDown() {
        _ = editor.handle(key: .arrowDown)
        updateAutocomplete()
    }

    public func setInputBuffer(_ text: String) {
        editor.set(text: text)
        updateAutocomplete()
    }

    // MARK: - Readline editing

    /// Move the cursor to the start of the input (Ctrl+A / Home).
    public func moveCursorToStart() {
        _ = editor.handle(key: .ctrlA)
        redraw()
    }

    /// Move the cursor to the end of the input (Ctrl+E / End).
    public func moveCursorToEnd() {
        _ = editor.handle(key: .ctrlE)
        redraw()
    }

    /// Delete from the cursor to the end of the line (Ctrl+K).
    public func clearLineAfterCursor() {
        _ = editor.handle(key: .ctrlK)
        updateAutocomplete()
    }

    /// Delete from the start of the line to the cursor (Ctrl+U).
    public func clearLineBeforeCursor() {
        _ = editor.handle(key: .ctrlU)
        updateAutocomplete()
    }

    /// Delete the word immediately before the cursor (Ctrl+W).
    public func deleteWordBefore() {
        _ = editor.handle(key: .ctrlW)
        updateAutocomplete()
    }

    /// Insert a multi-character string at the current cursor position (e.g. from paste).
    public func insertText(_ text: String) {
        let cleanText = text.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
        _ = editor.handle(key: .paste(cleanText))
        updateAutocomplete()
    }

    /// Clear the entire conversation (content lines + history). Does not reset input.
    public func clearConversation() {
        contentLines = []
        history = []
        terminal.write("\u{001B}[2J\u{001B}[H")
        renderedFooterLineCount = 0
        renderedCursorFooterRow = 0
        redraw()
    }

    public func submitInput() -> String? {
        let text = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        editor.clear()
        return text
    }

    /// If the character immediately before the cursor is `\`, replace it with a newline
    /// and return `true` (caller should skip submission). Returns `false` otherwise.
    public func convertBackslashToNewline() -> Bool {
        let pos = cursorPos
        guard pos > 0 else { return false }
        let text = inputBuffer
        let prevIdx = text.index(text.startIndex, offsetBy: pos - 1)
        guard text[prevIdx] == "\\" else { return false }
        var newText = text
        newText.replaceSubrange(prevIdx...prevIdx, with: "\n")
        editor.setText(newText, cursorOffset: pos)
        return true
    }

    public func setGenerating(_ flag: Bool) {
        if flag { isStreamingAborted = false }
        streaming.isGenerating = flag
        if !flag { streaming.reset() }
    }

    /// Atomically abort any in-flight generation: gate future stream/think chunks,
    /// clear all partial state, print "· Aborted", and redraw the clean footer.
    /// Because this runs inside the actor, any appendStreamChunk / appendThinkChunk
    /// calls that are already queued on the actor will execute AFTER this method
    /// sets isStreamingAborted = true, so they become no-ops.
    public func abortGeneration() {
        isStreamingAborted = true
        streaming.isGenerating = false
        streaming.reset()
        streaming.currentThinking = nil
        thinkLineBuffer = ""
        printScrollLine("\(DesignSystem.dim)· Aborted\(DesignSystem.reset)")
        redraw()
    }

    /// Append a raw chunk to the current streaming line (no space prefix).
    ///
    /// Use this for tokenised model output where the tokeniser already embeds
    /// any required whitespace inside each chunk.  Unlike ``appendStreamWord``,
    /// no space is inserted between consecutive calls.
    public func appendStreamChunk(_ chunk: String) {
        guard !isStreamingAborted else { return }
        let parts = chunk.split(separator: "\n", omittingEmptySubsequences: false)
        var committedLines: [String] = []

        for (i, part) in parts.enumerated() {
            if i > 0 {
                if !streaming.currentLine.isEmpty {
                    committedLines.append(streaming.formatter.format(streaming.currentLine))
                    streaming.currentLine = ""
                } else {
                    committedLines.append("")
                }
            }

            let fragment = String(part)
            guard !fragment.isEmpty else { continue }

            let candidate = streaming.currentLine + fragment   // raw concat — no space
            let maxWidth  = max(1, cols - 2)
            if VisibleWidth.measure(candidate) > maxWidth {
                if !streaming.currentLine.isEmpty {
                    committedLines.append(streaming.formatter.format(streaming.currentLine))
                    streaming.currentLine = fragment
                } else {
                    committedLines.append(streaming.formatter.format(fragment))
                    streaming.currentLine = ""
                }
            } else {
                streaming.currentLine = candidate
            }
        }

        if committedLines.isEmpty {
            redraw()
        } else {
            contentLines.append(contentsOf: committedLines)
            emitContentLines(committedLines)
        }
    }

    /// Append a word to the current streaming line. Handles embedded newlines.
    /// Auto-wraps when the line exceeds terminal width.
    public func appendStreamWord(_ word: String) {
        let parts = word.split(separator: "\n", omittingEmptySubsequences: false)
        var committedLines: [String] = []

        for (i, part) in parts.enumerated() {
            if i > 0 {
                if !streaming.currentLine.isEmpty {
                    committedLines.append(streaming.formatter.format(streaming.currentLine))
                    streaming.currentLine = ""
                } else {
                    committedLines.append("")
                }
            }

            let fragment = String(part)
            guard !fragment.isEmpty else { continue }

            let candidate = streaming.currentLine.isEmpty
                ? fragment
                : streaming.currentLine + " " + fragment
            let maxWidth  = max(1, cols - 2)
            // Use VisibleWidth so wide characters / emoji wrap at the correct column.
            // Drop the previous `&& !currentStreamLine.isEmpty` guard: if a single
            // fragment already exceeds maxWidth on an empty line, we still need to
            // commit it (truncated will be re-wrapped downstream by emitContentLines).
            if VisibleWidth.measure(candidate) > maxWidth {
                if !streaming.currentLine.isEmpty {
                    committedLines.append(streaming.formatter.format(streaming.currentLine))
                    streaming.currentLine = fragment
                } else {
                    // Single fragment wider than the line — emit it on its own
                    // and let downstream wrapping deal with it.
                    committedLines.append(streaming.formatter.format(fragment))
                    streaming.currentLine = ""
                }
            } else {
                streaming.currentLine = candidate
            }
        }

        if committedLines.isEmpty {
            redraw()
        } else {
            contentLines.append(contentsOf: committedLines)
            emitContentLines(committedLines)
        }
    }

    /// Flush any remaining partial stream line into contentLines and emit it above the footer.
    public func flushStreamLine() {
        guard !streaming.currentLine.isEmpty else { return }
        let committed = streaming.formatter.format(streaming.currentLine)
        streaming.currentLine = ""
        printScrollLine(committed)
    }

    /// Append a chunk of thinking text. Unlike `appendStreamChunk` — which buffers
    /// in the footer stream zone — this method commits each *complete* think line
    /// directly into the scroll area so the user sees it arrive in real time.
    /// The partial (incomplete) line is kept in `thinkLineBuffer` and displayed
    /// as a tail in the spinner label until the next newline or `flushThinkLine`.
    ///
    /// Think lines are styled as `dim + "∣ " + content` to visually distinguish
    /// them from the regular assistant response.
    public func appendThinkChunk(_ chunk: String) {
        guard !isStreamingAborted else { return }
        thinkLineBuffer += chunk
        // Split on newlines: all parts except the last are complete lines.
        let parts = thinkLineBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else {
            // No newline yet — just update the spinner label tail.
            redraw()
            return
        }
        // Commit all complete lines to scroll.
        let completeLines = parts.dropLast()
        let remaining     = parts.last ?? ""
        let styled = completeLines.map { formatThinkLine($0) }
        for line in styled {
            contentLines.append(line)
        }
        thinkLineBuffer = remaining
        emitContentLines(styled)
    }

    /// Flush any remaining partial think line to scroll and clear the buffer.
    public func flushThinkLine() {
        guard !thinkLineBuffer.isEmpty else { return }
        let line = formatThinkLine(thinkLineBuffer)
        thinkLineBuffer = ""
        contentLines.append(line)
        emitContentLines([line])
    }

    private func formatThinkLine(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .init(charactersIn: "\r"))
        return "\(DesignSystem.dim)∣ \(text)\(DesignSystem.reset)"
    }

    public func setThinking(_ note: String) {
        streaming.currentThinking = note
    }

    /// Show or clear an ephemeral one-line status notice in the footer area.
    ///
    /// Unlike `setThinking(_:)`, the notice is rendered as a plain line with
    /// no spinner glyph and no `(esc · Ns)` elapsed-time suffix. It is shown
    /// regardless of `setGenerating(_:)` state, so it is suitable for
    /// transient UI affordances that are unrelated to model generation
    /// (e.g. "🎤 Listening… press Enter to finish").
    ///
    /// The caller owns styling — pass a fully ANSI-styled string (including
    /// reset) to control colours.
    ///
    /// Pass `nil` (or an empty string) to clear the notice.
    public func setStatusNotice(_ text: String?) {
        if let text, !text.isEmpty {
            statusNotice = text
        } else {
            statusNotice = nil
        }
        redraw()
    }

    public func advanceSpinner() {
        streaming.advanceSpinner()
    }

    public func cycleMode(reverse: Bool = false) {
        let count = config.modes.count
        guard count > 0 else { return }
        if reverse {
            currentModeIndex = (currentModeIndex - 1 + count) % count
        } else {
            currentModeIndex = (currentModeIndex + 1) % count
        }
        redraw()
    }

    /// Set the current mode by index. Clamps to valid range.
    public func setCurrentModeIndex(_ index: Int) {
        guard !config.modes.isEmpty else { return }
        currentModeIndex = max(0, min(index, config.modes.count - 1))
        redraw()
    }

    /// Returns the total number of configured modes.
    public func getModeCount() -> Int { config.modes.count }
    public func getConfigModelCount() -> Int { config.models.count }

    public func cycleModel(reverse: Bool = false) {
        let count = config.models.count
        guard count > 0 else { return }
        if reverse {
            currentModelIndex = (currentModelIndex - 1 + count) % count
        } else {
            currentModelIndex = (currentModelIndex + 1) % count
        }
        redraw()
    }

    /// Set the current model by index. Clamps to valid range.
    /// Clears any label override set by `setModelLabel(_:)`.
    public func setCurrentModelIndex(_ index: Int) {
        guard !config.models.isEmpty else { return }
        currentModelIndex = max(0, min(index, config.models.count - 1))
        modelLabelOverride = nil
        redraw()
    }

    /// Override the model label shown in the status bar without changing the
    /// backing index. Use for dynamic/synthetic models not present in the
    /// AppConfig. Pass `nil` to revert to the index-based label.
    public func setModelLabel(_ label: String?) {
        modelLabelOverride = label
        redraw()
    }

    public func setPendingCount(_ count: Int) {
        streaming.pendingCount = count
    }

    public func isAutopilotEnabled() -> Bool {
        isAutopilot
    }

    public func setAutopilot(_ flag: Bool) {
        isAutopilot = flag
        redraw()
    }

    public func requestApproval(tool: String, args: String, isPlanMode: Bool = false) {
        approval = isPlanMode
            ? ApprovalState.makePlanMode(tool: tool, args: args)
            : ApprovalState.make(tool: tool, args: args)
        redraw()
    }

    public func clearApproval() {
        approval = nil
        redraw()
    }

    public func moveApprovalSelection(offset: Int) {
        guard var req = approval else { return }
        req.move(offset: offset)
        approval = req
        redraw()
    }

    public func getApprovalSelection() -> Int? {
        approval?.selected
    }

    public func getApprovalIsPlanMode() -> Bool {
        approval?.isPlanMode ?? false
    }

    public func getApprovalOptionCount() -> Int {
        approval?.options.count ?? 0
    }

    // MARK: - Option select (generic picker for git setup, branch selection, etc.)

    public func requestOptionSelect(prompt: String, options: [String], escSelectsLastOption: Bool = false) {
        optionSelect = OptionSelectState(prompt: prompt, options: options, selected: 0, escSelectsLastOption: escSelectsLastOption)
        redraw()
    }

    public func clearOptionSelect() {
        optionSelect = nil
        redraw()
    }

    public func moveOptionSelectSelection(offset: Int) {
        guard var req = optionSelect else { return }
        req.move(offset: offset)
        optionSelect = req
        redraw()
    }

    public func getOptionSelectSelection() -> Int {
        optionSelect?.selected ?? 0
    }

    public func getOptionSelectOptionCount() -> Int {
        optionSelect?.options.count ?? 0
    }

    public func getOptionSelectEscSelectsLastOption() -> Bool {
        optionSelect?.escSelectsLastOption ?? false
    }

    public func getCurrentModeBadgeColor() -> String {
        currentMode.badgeColor
    }

    /// Returns the label of the currently active model.
    public func getCurrentModelLabel() -> String { activeModelLabel }

    /// Returns the label of the currently active thinking mode.
    public func getCurrentModeLabel() -> String { currentMode.label }

    /// Returns the number of entries in the session history.
    public func getHistoryCount() -> Int { history.count }

    public func addHistoryEntry(_ entry: SessionEntry) {
        history.append(entry)
    }

    // MARK: - Voice Input

    /// Trigger the configured ``VoiceInputProvider`` to transcribe speech and
    /// prefill the input buffer with the result.
    ///
    /// Call this in response to ``Keystroke/ctrlV``.  The method is a no-op
    /// when no provider has been configured in ``AppConfig/voiceInputProvider``.
    ///
    /// During transcription the spinner is shown with a "Listening…" label so
    /// the user has visual feedback.  On success the input buffer is set to the
    /// transcription.  On failure the error message is appended to history.
    ///
    /// - Returns: `true` if a provider is configured and a transcription was
    ///   attempted (regardless of success), `false` when no provider is set.
    @discardableResult
    public func triggerVoiceInput() async -> Bool {
        guard let provider = config.voiceInputProvider else { return false }
        setGenerating(true)
        setThinking("Listening…")
        do {
            let transcription = try await provider.transcribe()
            setGenerating(false)
            setInputBuffer(transcription)
            moveCursorToEnd()
        } catch {
            setGenerating(false)
            let errorEntry = SessionEntry(
                role: .assistant,
                content: "🎤 Voice input failed: \(error.localizedDescription)"
            )
            addHistoryEntry(errorEntry)
        }
        redraw()
        return true
    }

    /// Add one or more lines (split on `\n`) to the content buffer and emit them above the footer.
    public func printScrollLine(_ text: String) {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = wrappedContentLines(rawLines)
        contentLines.append(contentsOf: newLines)
        emitContentLines(newLines, trigger: "printScrollLine")
    }

    /// Append multiple pre-formatted lines in a single batch above the footer.
    public func printScrollLines(_ lines: [String]) {
        let wrapped = wrappedContentLines(lines)
        guard !wrapped.isEmpty else { return }
        contentLines.append(contentsOf: wrapped)
        emitContentLines(wrapped, trigger: "printScrollLines")
    }

    /// Wraps scroll-content lines to terminal width so terminal auto-wrap does
    /// not consume hidden extra rows and desynchronize footer cursor math.
    private func wrappedContentLines(_ lines: [String]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(lines.count)
        // Keep one column of headroom so emitted content never auto-wraps at
        // exactly terminal width (which would break footer cursor-row math).
        let width = max(1, cols - 1)
        for line in lines {
            let wrapped = AnsiWrapping.wrap(line, width: width, breakOnWords: true)
            if wrapped.isEmpty { out.append("") }
            else { out.append(contentsOf: wrapped) }
        }
        return out
    }

    // MARK: - Footer Rendering Engine

    private let maxAutocompleteVisible = 8

    private func noteFooterRender(trigger: String) {
        footerRenderSequence += 1
        footerRenderTrigger = trigger
    }

    private static func cursorUp(_ n: Int) -> String {
        n <= 0 ? "" : "\u{001B}[\(n)A"
    }

    private static func cursorDown(_ n: Int) -> String {
        n <= 0 ? "" : "\u{001B}[\(n)B"
    }

    private func prefixAndDisplayBuffer() -> (pfxLen: Int, displayBuffer: String) {
        if inputBuffer.hasPrefix("!!") {
            return (DesignSystem.UI.shellExcludedPrefix.count, String(inputBuffer.dropFirst(2)))
        } else if inputBuffer.hasPrefix("!") {
            return (DesignSystem.UI.shellPrefix.count, String(inputBuffer.dropFirst(1)))
        } else if isAutopilot {
            return (DesignSystem.UI.autopilotPrefix.count, inputBuffer)
        } else {
            return (DesignSystem.UI.defaultPrefix.count, inputBuffer)
        }
    }

    /// Build the footer block as a flat array of ANSI-styled lines (one per terminal row).
    ///
    /// Footer structure (bottom-up numbering from status bar):
    ///   status bar · bottom separator · input lines · top separator · popups · spinner · stream line
    private func buildFooterLines() -> [String] {
        let inputLinesList = inputBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines: [String] = []

        // Live stream line (partial line being written by the AI)
        if !streaming.currentLine.isEmpty {
            lines.append(streaming.formatter.formatPreview(streaming.currentLine))
        }

        // Partial think line — current reasoning line not yet terminated by \n.
        // Without this, thinking text is invisible until a newline arrives.
        if !thinkLineBuffer.isEmpty {
            // Keep footer layout math stable: never let a single logical footer
            // line auto-wrap at the terminal layer, otherwise redraw cursor math
            // (which counts logical lines) drifts and can duplicate content.
            let wrappedThink = AnsiWrapping.wrap(
                thinkLineBuffer,
                width: max(1, cols - 2),  // account for "∣ " prefix width
                breakOnWords: true
            )
            if wrappedThink.isEmpty {
                lines.append(formatThinkLine(thinkLineBuffer))
            } else {
                for line in wrappedThink {
                    lines.append(formatThinkLine(line))
                }
            }
        }

        // Ephemeral status notice — plain line, no framing. Rendered above
        // the spinner so it remains visible even while generation is active.
        if let notice = statusNotice, !notice.isEmpty {
            lines.append(notice)
        }

        // Spinner / thinking indicator
        if streaming.isGenerating && approval == nil {
            let frame = streaming.spinnerFrame
            let stepLabel = streaming.thinkingLabel
            let pendingNote = streaming.pendingCount > 0
                ? "  \(DesignSystem.darkGray)[\(streaming.pendingCount) queued]\(DesignSystem.reset)"
                : ""
            let elapsed = streaming.elapsedDisplaySeconds
            lines.append("\(DesignSystem.yellow)\(frame) \(stepLabel)  \(DesignSystem.darkGray)(esc · \(elapsed)s)\(DesignSystem.reset)\(pendingNote)")
        }

        // Tool-approval UI (message + options + prompt)
        if let req = approval {
            lines.append("\(DesignSystem.brightYellow)\(req.message)\(DesignSystem.reset)")
            for (i, opt) in req.options.enumerated() {
                let marker = (i == req.selected) ? "● " : "  "
                let style  = (i == req.selected) ? DesignSystem.brightWhite : DesignSystem.dim
                lines.append("\(style)\(marker)\(i + 1). \(opt)\(DesignSystem.reset)")
            }
            let digits = (1...req.options.count).map(String.init).joined(separator: "/")
            lines.append("\(DesignSystem.darkGray)Use \(digits), arrows, Enter, or Esc. Waiting for user confirmation... [\(req.selected + 1)/\(req.options.count)]:\(DesignSystem.reset)")
        } else if let req = optionSelect {
            lines.append("\(DesignSystem.brightYellow)\(req.prompt)\(DesignSystem.reset)")
            for (i, opt) in req.options.enumerated() {
                let marker = (i == req.selected) ? "● " : "  "
                let style  = (i == req.selected) ? DesignSystem.brightWhite : DesignSystem.dim
                lines.append("\(style)\(marker)\(i + 1). \(opt)\(DesignSystem.reset)")
            }
            let digits = (1...req.options.count).map(String.init).joined(separator: "/")
            let escHint = req.escSelectsLastOption ? "Esc selects last" : "Esc cancels"
            lines.append("\(DesignSystem.darkGray)Use \(digits), arrows, Enter, or Esc (\(escHint)). [\(req.selected + 1)/\(req.options.count)]:\(DesignSystem.reset)")
        }

        // Command autocomplete popup
        let visibleCommandCount = min(autocomplete.filteredCommands.count, maxAutocompleteVisible)
        if !autocomplete.filteredCommands.isEmpty {
            let windowStart  = max(0, min(autocomplete.selectedIndex - visibleCommandCount + 1,
                                         autocomplete.filteredCommands.count - visibleCommandCount))
            let windowEnd    = min(windowStart + visibleCommandCount, autocomplete.filteredCommands.count)
            let showUp       = windowStart > 0
            let showDown     = windowEnd < autocomplete.filteredCommands.count
            let upArrow      = showUp   ? "\(DesignSystem.brightYellow)↑\(DesignSystem.reset)" : "\(DesignSystem.dim)↑\(DesignSystem.reset)"
            let downArrow    = showDown ? "\(DesignSystem.brightYellow)↓\(DesignSystem.reset)" : "\(DesignSystem.dim)↓\(DesignSystem.reset)"
            let counter      = "\(DesignSystem.darkGray)(\(autocomplete.selectedIndex + 1)/\(autocomplete.filteredCommands.count))\(DesignSystem.reset)"
            let counterPlain = "(\(autocomplete.selectedIndex + 1)/\(autocomplete.filteredCommands.count))"
            let leftBlock    = " \(upArrow) \(downArrow)  \(counter) "
            let leftPlain    = " ↑ ↓  \(counterPlain) "
            lines.append("\(leftBlock)\(DesignSystem.dim)\(String(repeating: "─", count: max(0, cols - VisibleWidth.measure(leftPlain))))\(DesignSystem.reset)")
            // Width of the widest command name in the visible window — used for
            // description column alignment. `+ 2` adds a minimum gap.
            let nameColWidth = (windowStart..<windowEnd)
                .map { VisibleWidth.measure(autocomplete.filteredCommands[$0].name) }
                .max() ?? 0
            let descColumn = nameColWidth + 2
            for cmdIndex in windowStart..<windowEnd {
                let cmd        = autocomplete.filteredCommands[cmdIndex]
                let isSelected = (cmdIndex == autocomplete.selectedIndex)
                let marker     = isSelected ? "\(DesignSystem.brightYellow)▎ ❯ \(DesignSystem.reset)" : "\(DesignSystem.dim)▎   \(DesignSystem.reset)"
                let name       = isSelected ? "\(DesignSystem.brightWhite)\(cmd.name)\(DesignSystem.reset)" : "\(DesignSystem.dim)\(cmd.name)\(DesignSystem.reset)"
                let desc       = "\(DesignSystem.darkGray)\(cmd.desc)\(DesignSystem.reset)"
                let pad        = max(1, descColumn - VisibleWidth.measure(cmd.name))
                lines.append("\(marker)\(name)\(String(repeating: " ", count: pad))\(desc)")
            }
        }

        // Help menu
        if autocomplete.showHelpMenu {
            lines.append("\(DesignSystem.dim)▎   ── Keyboard Shortcuts \(String(repeating: "─", count: max(0, cols - 27)))\(DesignSystem.reset)")
            for shortcut in config.keyboardShortcuts {
                let pad = max(0, 38 - shortcut.key.count)
                lines.append("\(DesignSystem.dim)▎   \(shortcut.key)\(String(repeating: " ", count: pad))\(DesignSystem.darkGray)\(shortcut.description)\(DesignSystem.reset)")
            }
        }

        // Render signal (debug): identify what triggered this top-bar render.
        if config.topBarDebugEnabled {
            let signal = "\(DesignSystem.darkGray)⟦tb#\(footerRenderSequence) \(footerRenderTrigger)⟧\(DesignSystem.reset)"
            lines.append(TruncatedText.render(signal, width: max(1, cols - 1)))
        }

        // Top separator. Keep one column shy of full width to avoid terminals
        // that auto-wrap exactly-at-column-width lines, which breaks cursor math.
        let separatorWidth = max(1, cols - 1)
        lines.append(currentMode.barColor + String(repeating: "─", count: separatorWidth) + DesignSystem.reset)

        // Input lines
        for (i, line) in inputLinesList.enumerated() {
            let prefix: String
            let displayLine: String
            if i == 0 {
                if inputBuffer.hasPrefix("!!") {
                    prefix = DesignSystem.UI.shellExcludedPrefix
                    displayLine = String(line.dropFirst(2))
                } else if inputBuffer.hasPrefix("!") {
                    prefix = DesignSystem.UI.shellPrefix
                    displayLine = String(line.dropFirst(1))
                } else if isAutopilot {
                    prefix = DesignSystem.UI.autopilotPrefix
                    displayLine = String(line)
                } else {
                    prefix = DesignSystem.UI.defaultPrefix
                    displayLine = String(line)
                }
            } else {
                prefix = "  "
                displayLine = String(line)
            }
            var inputLine = DesignSystem.brightWhite + prefix + displayLine + DesignSystem.reset
            if i == 0, let suggestion = autocomplete.ghostSuggestion {
                inputLine += DesignSystem.darkGray + suggestion + DesignSystem.reset
            }
            lines.append(inputLine)
        }

        // Bottom separator (same auto-wrap safeguard as top separator).
        lines.append(currentMode.barColor + String(repeating: "─", count: separatorWidth) + DesignSystem.reset)

        // Status line — activeFile folded in after the branch name
        let pathStr   = statusBar.abbreviatedPath()
        let branchStr = statusBar.gitBranch.map { " (\($0))" } ?? ""
        let fileStr   = statusBar.activeFile.map {
            let name = ($0 as NSString).lastPathComponent
            return "  \(DesignSystem.darkGray)›\(DesignSystem.reset)  \(DesignSystem.brightCyan)\(name)\(DesignSystem.reset)"
        } ?? ""
        let modePrefix = statusBar.modeLabel.isEmpty ? "" : "\(statusBar.modeLabel) · "
        let leftContent = "\(modePrefix)/ commands  ·  ?  ·  \(pathStr)\(branchStr)"
        let leftStatus  = "\(DesignSystem.darkGray)\(leftContent)\(DesignSystem.reset)\(fileStr)"
        let footerWidth = max(1, cols - 1)
        let rightStatus = buildRightStatus(maxWidth: footerWidth)
        let rightWidth = VisibleWidth.measure(rightStatus.plain)
        let leftWidth = max(0, footerWidth - rightWidth - 1)
        var statusLine = ""
        if leftWidth > 0 {
            statusLine += TruncatedText.render(leftStatus, width: leftWidth)
            statusLine += " "
        }
        statusLine += rightStatus.ansi
        lines.append(statusLine)

        // Clamp every footer line to a safe width to prevent terminal
        // auto-wrap from creating hidden extra rows that desync redraw math.
        return lines.map { TruncatedText.render($0, width: footerWidth) }
    }

    /// Build a right status string that keeps `[model](mode)` visible.
    /// Optional extras are dropped first when space is constrained.
    private func buildRightStatus(maxWidth: Int) -> (ansi: String, plain: String) {
        let width = max(1, maxWidth)
        let mode = buildModeBadge()
        var extras: [(ansi: String, plain: String)] = []
        if let ctx = statusBar.contextPercent {
            let ctxText = String(format: "%.1f%% ctx", ctx)
            extras.append((
                "\(DesignSystem.darkGray)[\(ctxText)]\(DesignSystem.reset)",
                "[\(ctxText)]"
            ))
        }
        let lockBadge: (ansi: String, plain: String)? = statusBar.sandboxEnabled.map { sandboxOn in
            let color = sandboxOn ? DesignSystem.green : DesignSystem.red
            let icon = sandboxOn ? "🔒" : "🔓"
            return ("\(color)\(icon)\(DesignSystem.reset)", icon)
        }

        func build(label: String, includeExtrasCount: Int) -> (ansi: String, plain: String) {
            var ansi = "\(DesignSystem.brightCyan)[\(label)]\(DesignSystem.reset)\(mode.ansi)"
            var plain = "[\(label)]\(mode.plain)"
            if includeExtrasCount > 0 {
                for extra in extras.prefix(includeExtrasCount) {
                    ansi += "  \(extra.ansi)"
                    plain += "  \(extra.plain)"
                }
            }
            if let lockBadge {
                ansi += "  \(lockBadge.ansi)"
                plain += "  \(lockBadge.plain)"
            }
            return (ansi, plain)
        }

        func staticSuffixWidth(includeExtrasCount: Int) -> Int {
            var plain = "[]\(mode.plain)"
            if includeExtrasCount > 0 {
                for extra in extras.prefix(includeExtrasCount) {
                    plain += "  \(extra.plain)"
                }
            }
            if let lockBadge {
                plain += "  \(lockBadge.plain)"
            }
            return VisibleWidth.measure(plain)
        }

        var includeExtrasCount = extras.count
        while includeExtrasCount >= 0 {
            let noTruncation = build(label: activeModelLabel, includeExtrasCount: includeExtrasCount)
            if VisibleWidth.measure(noTruncation.plain) <= width {
                return noTruncation
            }

            let availableLabelWidth = max(1, width - staticSuffixWidth(includeExtrasCount: includeExtrasCount))
            let truncatedLabel = VisibleWidth.truncate(activeModelLabel, maxWidth: availableLabelWidth)
            let truncated = build(label: truncatedLabel, includeExtrasCount: includeExtrasCount)
            if VisibleWidth.measure(truncated.plain) <= width {
                return truncated
            }

            includeExtrasCount -= 1
        }

        let minimal = build(label: "", includeExtrasCount: 0)
        if VisibleWidth.measure(minimal.plain) <= width { return minimal }
        return ("\(mode.ansi)", mode.plain)
    }

    /// Build the active mode badge for the status bar.
    private func buildModeBadge() -> (ansi: String, plain: String) {
        ("\(currentMode.badgeColor)(\(currentMode.label))\(DesignSystem.reset)",
         "(\(currentMode.label))")
    }

    /// Compute the cursor location within the footer and target input column.
    private func footerCursorPlacement(footerLineCount: Int) -> (row: Int, column: Int) {
        let inputLinesList = inputBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let inputLineCount = max(1, inputLinesList.count)
        let (pfxLen, displayBuffer) = prefixAndDisplayBuffer()
        let adjustedPos  = max(0, cursorPos - (inputBuffer.count - displayBuffer.count))
        let linesBefore  = displayBuffer.prefix(adjustedPos)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let curRowInInput = max(0, linesBefore.count - 1)
        let curColInLine  = linesBefore.last?.count ?? 0

        // Footer layout (0-indexed from top):
        //   [popups / stream / spinner] · top-sep · input[0..n] · bot-sep · status
        // status = footerLineCount - 1
        // bot-sep = footerLineCount - 2
        // last input = footerLineCount - 3
        // first input = footerLineCount - 2 - inputLineCount
        let cursorFooterRow = footerLineCount - 2 - inputLineCount + curRowInInput
        let cursorColumn = pfxLen + curColInLine + 1
        return (cursorFooterRow, cursorColumn)
    }

    /// Emit the footer block starting from the current cursor position (footer top).
    ///
    /// - Parameters:
    ///   - footerLines: Lines produced by `buildFooterLines()`.
    ///   - previousCount: How many lines the previous footer occupied from this position.
    ///                    Used to clear leftover lines when the footer shrinks.
    /// - Returns: The ANSI string to write, and the row index within the footer where the
    ///            cursor will land (needed for the next `redraw()` cursor-up calculation).
    private func renderFooterBlock(_ footerLines: [String], previousCount: Int) -> (String, Int) {
        var out = ""
        for (i, line) in footerLines.enumerated() {
            out += "\r\u{001B}[K\(line)"
            if i < footerLines.count - 1 { out += "\r\n" }
        }

        // If the footer shrank, clear only the leftover physical lines below
        // the new status row. Avoid ED (ESC[0J): if cursor tracking drifts,
        // ED can wipe visible transcript rows in the viewport.
        if previousCount > footerLines.count {
            let extraLines = previousCount - footerLines.count
            out += Self.cursorDown(1)
            for i in 0..<extraLines {
                out += "\r\u{001B}[K"
                if i < extraLines - 1 {
                    out += Self.cursorDown(1)
                }
            }
            out += "\r" + Self.cursorUp(extraLines)
        }

        // Cursor is now on the status bar (index footerLines.count - 1).
        // Move it to the correct position within the input field.
        let placement = footerCursorPlacement(footerLineCount: footerLines.count)
        let cursorFooterRow = placement.row
        let linesUp = (footerLines.count - 1) - cursorFooterRow
        if linesUp > 0 {
            out += "\r" + Self.cursorUp(linesUp)
        } else {
            out += "\r"
        }
        out += "\u{001B}[\(placement.column)G"
        out += EscapeSequence.showCursor()
        return (out, cursorFooterRow)
    }

    /// Repaint footer from absolute rows after a resize.
    ///
    /// On shrink, previously drawn footer lines can reflow into multiple
    /// physical rows. Estimate and clear that wrapped footprint before drawing
    /// the new footer so stale separators don't remain in the viewport.
    private func redrawAfterResize(oldRows: Int, oldCols: Int, footerLines: [String]) -> (String, Int) {
        let safeRows = max(1, rows)
        let oldFooterCols = max(1, oldCols - 1)
        let newFooterCols = max(1, cols - 1)
        let wrapFactor = max(1, Int(ceil(Double(oldFooterCols) / Double(newFooterCols))))
        let estimatedOldFooterRows = max(0, min(oldRows, renderedFooterLineCount * wrapFactor))
        let linesToClear = max(footerLines.count, estimatedOldFooterRows)

        var out = EscapeSequence.hideCursor()
        if linesToClear > 0 {
            let clearStart = max(1, safeRows - linesToClear + 1)
            for row in clearStart...safeRows {
                out += EscapeSequence.moveTo(row: row, col: 1)
                out += EscapeSequence.clearLine()
            }
        }

        let footerStartRow = max(1, safeRows - footerLines.count + 1)
        for (i, line) in footerLines.enumerated() {
            let row = footerStartRow + i
            guard row >= 1, row <= safeRows else { continue }
            out += EscapeSequence.moveTo(row: row, col: 1)
            out += "\u{001B}[K\(line)"
        }

        let placement = footerCursorPlacement(footerLineCount: footerLines.count)
        let cursorTerminalRow = max(1, min(safeRows, footerStartRow + placement.row))
        out += EscapeSequence.moveTo(row: cursorTerminalRow, col: 1)
        out += "\u{001B}[\(placement.column)G"
        out += EscapeSequence.showCursor()
        return (out, placement.row)
    }

    /// Redraw only the footer block in-place using relative cursor movement.
    /// Content lines already in the terminal scrollback are never touched.
    private func redraw(trigger: String = "redraw") {
        terminal.beginFrame()
        defer { terminal.endFrame() }
        noteFooterRender(trigger: trigger)

        let footerLines = buildFooterLines()
        var out = EscapeSequence.hideCursor()

        // Move to the top of the currently rendered footer block.
        if renderedCursorFooterRow > 0 {
            out += "\r" + Self.cursorUp(renderedCursorFooterRow)
        } else {
            out += "\r"
        }

        let (footerOut, newCursorRow) = renderFooterBlock(footerLines, previousCount: renderedFooterLineCount)
        out += footerOut
        renderedFooterLineCount = footerLines.count
        renderedCursorFooterRow = newCursorRow
        terminal.write(out)
    }

    /// Emit `newLines` to the terminal body above the footer, then reprint the footer.
    /// Called by `printScrollLine`, `printScrollLines`, and `appendStreamWord`.
    private func emitContentLines(_ newLines: [String], trigger: String = "emitContentLines") {
        terminal.beginFrame()
        defer { terminal.endFrame() }
        noteFooterRender(trigger: "\(trigger)[\(newLines.count)]")

        // Normalize to width-safe physical rows so row accounting below matches
        // what the terminal actually paints.
        let emittedLines = wrappedContentLines(newLines)

        let footerLines = buildFooterLines()
        var out = EscapeSequence.hideCursor()

        // Move to the top of the footer block.
        if renderedCursorFooterRow > 0 {
            out += "\r" + Self.cursorUp(renderedCursorFooterRow)
        } else {
            out += "\r"
        }

        // Print each new content line, replacing the top of the old footer
        // and pushing the rest of the footer down naturally.
        for line in emittedLines {
            out += "\r\u{001B}[K\(line)\r\n"
        }

        // Reprint footer.  The old footer lines from row newLines.count onwards
        // are still visible in the terminal — pass their count so renderFooterBlock
        // can clear any surplus if the new footer is shorter.
        let remainingOldFooter = max(0, renderedFooterLineCount - emittedLines.count)
        let (footerOut, newCursorRow) = renderFooterBlock(footerLines, previousCount: remainingOldFooter)
        out += footerOut
        renderedFooterLineCount = footerLines.count
        renderedCursorFooterRow = newCursorRow
        terminal.write(out)
    }
    // MARK: - Public Render Methods

    /// Print the app's welcome banner using the configured name, version, and message.
    public func showWelcome() {
        printScrollLine("\(DesignSystem.brightYellow)\(config.appName) v\(config.version)\(DesignSystem.reset) — \(config.welcomeMessage)")
        printScrollLine("\(DesignSystem.darkGray)Enter send  ·  Ctrl+J / Shift+Enter new line  ·  ↑/↓ input history  ·  Shift+Tab mode  ·  Ctrl+P model  ·  Ctrl+C quit\(DesignSystem.reset)")
        printScrollLine("")
    }

    /// Render just the footer (lightweight, for keystrokes and spinner)
    public func renderFooter() {
        redraw(trigger: "renderFooter")
    }

    /// Initial screen setup — print a blank line then render the footer.
    /// No full-screen clear; the terminal's scrollback buffer is preserved.
    public func setupScreen() {
        terminal.write("\r\n")
        redraw(trigger: "setupScreen")
    }

    /// Teardown the footer UI without clearing any viewport content.
    ///
    /// We intentionally avoid erase-in-display sequences here because cursor
    /// drift can make them wipe visible transcript lines on exit.
    public func teardownScreen() {
        terminal.beginFrame()
        defer { terminal.endFrame() }

        var out = EscapeSequence.hideCursor()
        let linesDown = max(0, renderedFooterLineCount - 1 - renderedCursorFooterRow)
        out += "\r"
        if linesDown > 0 {
            out += "\u{001B}[\(linesDown)B"
        }
        out += "\r\n"
        out += EscapeSequence.showCursor()

        renderedFooterLineCount = 0
        renderedCursorFooterRow = 0
        terminal.write(out)
    }

    /// Handle terminal resize.
    ///
    /// Resize is rendered from absolute rows so stale relative cursor anchors
    /// from the old viewport cannot duplicate footer separators/input rows.
    public func handleResize(oldRows: Int, oldCols: Int) {
        terminal.beginFrame()
        defer { terminal.endFrame() }
        noteFooterRender(trigger: "handleResize")

        let footerLines = buildFooterLines()
        let (out, newCursorRow) = redrawAfterResize(oldRows: oldRows, oldCols: oldCols, footerLines: footerLines)
        renderedFooterLineCount = footerLines.count
        renderedCursorFooterRow = newCursorRow
        terminal.write(out)
    }

    /// Render the current spinner frame
    public func renderSpinnerTick() {
        guard streaming.isGenerating else { return }
        redraw(trigger: "renderSpinnerTick")
    }

    public func getCursorPos() -> Int { cursorPos }
    public func getIsGenerating() -> Bool { streaming.isGenerating }

    public func setActiveFile(_ file: String?) {
        statusBar.activeFile = file
        redraw(trigger: "setActiveFile")
    }

    public func setStatusModeLabel(_ label: String) {
        statusBar.modeLabel = label
        redraw(trigger: "setStatusModeLabel")
    }
}
