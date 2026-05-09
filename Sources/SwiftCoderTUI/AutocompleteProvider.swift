// MARK: - Autocomplete Types

/// A single completion item shown in the autocomplete popup.
public struct AutocompleteItem: Equatable, Sendable {
    /// Value inserted into the buffer when the item is accepted.
    public let value: String
    /// Label shown in the popup list.
    public let label: String
    /// Optional short description shown to the right of the label.
    public let description: String?

    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

/// The set of suggestions returned by a provider for a given cursor position.
public struct AutocompleteSuggestion: Sendable {
    /// Ordered list of completion candidates.
    public let items: [AutocompleteItem]
    /// The text prefix that was matched. Used to replace the right span when
    /// a completion is accepted.
    public let prefix: String

    public init(items: [AutocompleteItem], prefix: String) {
        self.items = items
        self.prefix = prefix
    }
}

// MARK: - SlashCommand

/// A slash command that can be registered with `CombinedAutocompleteProvider`.
///
/// Implement this protocol to add commands that appear when the user types `/`:
/// ```swift
/// struct HelpCommand: SlashCommand {
///     let name = "help"
///     let description: String? = "Show help"
///     func argumentCompletions(prefix: String) -> [AutocompleteItem] { [] }
/// }
/// ```
public protocol SlashCommand: Sendable {
    /// Command name without the leading `/` (e.g. `"review"`, `"test"`).
    var name: String { get }
    /// Short description shown in the autocomplete popup.
    var description: String? { get }
    /// Called when the user has typed `/name ` and is typing an argument.
    func argumentCompletions(prefix: String) -> [AutocompleteItem]
    /// When `true`, `argumentCompletions(prefix: "")` are shown directly in the
    /// slash-command list (as `/name arg` entries) instead of a single `/name` entry.
    /// Defaults to `false`.
    var expandsInlineWhenNoArg: Bool { get }
}

public extension SlashCommand {
    var expandsInlineWhenNoArg: Bool { false }
}

// MARK: - AutocompleteProvider Protocol

/// A type that produces autocomplete suggestions for the current input state.
///
/// Conform to this protocol and call `renderer.setAutocompleteProvider(_:)` to
/// replace the built-in AppConfig-based slash-command completion with your own
/// implementation (file paths, `@mentions`, AI model names, etc.).
///
/// ```swift
/// let provider = CombinedAutocompleteProvider(commands: [HelpCommand(), ReviewCommand()])
/// await renderer.setAutocompleteProvider(provider)
/// ```
public protocol AutocompleteProvider: Sendable {
    /// Return suggestions for the current buffer state, or `nil` if nothing matches.
    ///
    /// - Parameters:
    ///   - lines:      All lines of the input buffer.
    ///   - cursorLine: Zero-based line index where the cursor sits.
    ///   - cursorCol:  Zero-based column (character offset) within `lines[cursorLine]`.
    func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> AutocompleteSuggestion?

    /// Apply a chosen completion item to the buffer, returning the updated state.
    ///
    /// The default implementation replaces the `prefix.count` characters immediately
    /// before the cursor with `item.value`.
    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int)

    /// Return file/path suggestions when the user explicitly requests completion
    /// (e.g. via Tab). Return `nil` to fall through to `getSuggestions`.
    func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> AutocompleteSuggestion?

    /// Return `false` to suppress file completion for slash-command argument
    /// positions (so Tab completes the command name, not a file path).
    func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> Bool
}

// MARK: - Default Implementations

public extension AutocompleteProvider {
    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        guard lines.indices.contains(cursorLine) else { return (lines, cursorLine, cursorCol) }
        var mutable = lines
        var line = mutable[cursorLine]
        let safePrefixCount = min(prefix.count, cursorCol)
        let start = line.index(line.startIndex, offsetBy: cursorCol - safePrefixCount)
        let end   = line.index(start, offsetBy: safePrefixCount)
        let replacement = completionString(prefix: prefix, item: item)
        line.replaceSubrange(start..<end, with: replacement)
        mutable[cursorLine] = line
        let newCursor = max(0, cursorCol - safePrefixCount + replacement.count)
        return (mutable, cursorLine, newCursor)
    }

    func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> AutocompleteSuggestion? { nil }

    func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> Bool { true }

    // Inserts trailing space after slash commands and @ values.
    private func completionString(prefix: String, item: AutocompleteItem) -> String {
        if prefix.hasPrefix("/"), !prefix.contains(" ") { return "/" + item.value + " " }
        if prefix.hasPrefix("@") {
            let isDirectory = item.description == "directory" || item.value.hasSuffix("/")
            return isDirectory ? "@" + item.value : "@" + item.value + " "
        }
        return item.value
    }
}
