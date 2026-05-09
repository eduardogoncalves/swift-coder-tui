import Foundation

/// All state that drives the autocomplete popup, ghost text, and `?` help menu.
///
/// Extracted from `Renderer` so the actor doesn't own seven loose stored
/// properties for one feature. The struct is a pure value type: every mutation
/// is local, and the renderer composes it back into the footer at paint time.
struct AutocompleteState {
    /// Items shown in the popup, paired with their description for layout.
    var filteredCommands: [(name: String, desc: String)] = []

    /// Source items when an external `AutocompleteProvider` is active. Parallel
    /// to `filteredCommands` — preserves the original `value` for completion.
    var filteredItems: [AutocompleteItem] = []

    var selectedIndex: Int = 0

    /// Inline ghost-text suggestion appended after the cursor (AppConfig mode).
    var ghostSuggestion: String? = nil

    /// Prefix matched by the external provider — used when applying completion.
    var externalPrefix: String = ""

    /// `?`-triggered keyboard-shortcut help overlay.
    var showHelpMenu: Bool = false

    var isActive: Bool { !filteredCommands.isEmpty || showHelpMenu }

    mutating func reset() {
        filteredCommands = []
        filteredItems = []
        ghostSuggestion = nil
        externalPrefix = ""
        showHelpMenu = false
    }

    mutating func showHelp() {
        showHelpMenu = true
        filteredCommands = []
        ghostSuggestion = nil
        externalPrefix = ""
    }

    mutating func setExternalSuggestion(items: [AutocompleteItem], prefix: String) {
        filteredItems = items
        filteredCommands = items.map { ($0.label, $0.description ?? "") }
        externalPrefix = prefix
        selectedIndex = 0
        ghostSuggestion = nil
    }

    mutating func clearExternal() {
        filteredItems = []
        filteredCommands = []
        ghostSuggestion = nil
        externalPrefix = ""
    }

    mutating func setAppConfigCommands(_ commands: [(name: String, desc: String)]) {
        filteredCommands = commands
        selectedIndex = 0
    }

    /// Recompute the inline ghost suggestion. No-op when an external provider is
    /// driving completion (ghost text only makes sense for AppConfig mode).
    mutating func recomputeGhost(buffer: String, hasExternalProvider: Bool) {
        guard !hasExternalProvider else { ghostSuggestion = nil; return }
        if selectedIndex >= 0 && selectedIndex < filteredCommands.count {
            let best = filteredCommands[selectedIndex]
            ghostSuggestion = String(best.name.dropFirst(buffer.count))
        } else {
            ghostSuggestion = nil
        }
    }

    /// Returns `true` when the selection actually moved (caller may want to redraw).
    mutating func moveSelection(offset: Int) -> Bool {
        guard !filteredCommands.isEmpty else { return false }
        selectedIndex = (selectedIndex + offset + filteredCommands.count) % filteredCommands.count
        return true
    }

    var selectedCommandName: String? {
        guard selectedIndex >= 0 && selectedIndex < filteredCommands.count else { return nil }
        return filteredCommands[selectedIndex].name
    }
}
