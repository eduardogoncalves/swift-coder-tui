import Foundation
import os

// MARK: - CombinedAutocompleteProvider

/// A ready-to-use `AutocompleteProvider` that combines:
///
/// - **Slash commands** — matches `/commandName` prefixes using registered ``SlashCommand``s
///   and static ``AutocompleteItem`` values.
/// - **File-path completion** — triggers on `./`, `~/`, `/`, or any bare path token
///   containing `/`.
/// - **`@mention` completion** — triggers on `@<path>` tokens and filters to
///   attachable file types.
///
/// Instantiate once and pass to `renderer.setAutocompleteProvider(_:)`:
/// ```swift
/// let provider = CombinedAutocompleteProvider(
///     commands: [ReviewCommand(), TestCommand()],
///     basePath: FileManager.default.currentDirectoryPath)
/// await renderer.setAutocompleteProvider(provider)
/// ```
public final class CombinedAutocompleteProvider: AutocompleteProvider, @unchecked Sendable {
    private let commands: [SlashCommand]
    private let staticCommands: [AutocompleteItem]
    private let baseURL: URL
    private let fileManager: FileManager

    private let attachmentRegex = try? NSRegularExpression(pattern: "@[^\\s]*$", options: [])
    // The pattern avoids nested quantifiers (which catastrophically backtrack on
    // inputs like "@file.swift " where the trailing space prevents $ from matching).
    // `[^\s"'=]*` already matches slashes so the path body is a single greedy group.
    private let pathRegex = try? NSRegularExpression(
        pattern: "(?:^|[\\s\"'=])((?:~\\/|\\.{0,2}\\/?)(?:[^\\s\"'=]*))$",
        options: [])

    // MARK: - Directory listing cache
    //
    // `fileSuggestions(for:)` is hit on every keystroke that contains a path
    // token. Without a cache, each keystroke triggers a full
    // `contentsOfDirectory` scan + 1 `resourceValues` syscall per entry — which
    // freezes the UI on large directories (e.g. node_modules, DerivedData).
    //
    // The cache keys on the directory's resolved path and is invalidated when
    // either the entry's TTL expires or the directory's mtime changes.
    private struct DirCacheEntry {
        let entries: [(name: String, isDirectory: Bool)]
        let mtime: Date
        let cachedAt: Date
    }
    private let dirCacheLock = OSAllocatedUnfairLock(initialState: [String: DirCacheEntry]())
    private static let cacheTTL: TimeInterval = 0.30

    private func listDirectory(_ url: URL) -> [(name: String, isDirectory: Bool)]? {
        let key = url.standardizedFileURL.path
        let now = Date()
        let currentMtime = (try? fileManager.attributesOfItem(atPath: key)[.modificationDate] as? Date) ?? .distantPast

        if let cached = dirCacheLock.withLock({ $0[key] }),
           now.timeIntervalSince(cached.cachedAt) < Self.cacheTTL,
           cached.mtime == currentMtime
        {
            return cached.entries
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        let entries: [(name: String, isDirectory: Bool)] = contents.map {
            let isDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return (name: $0.lastPathComponent, isDirectory: isDir)
        }

        dirCacheLock.withLock {
            $0[key] = DirCacheEntry(entries: entries, mtime: currentMtime, cachedAt: now)
        }

        return entries
    }

    /// - Parameters:
    ///   - commands:       Dynamic slash commands (see ``SlashCommand``).
    ///   - staticCommands: Fixed items shown when the user types `/`.
    ///   - basePath:       Root directory for relative path expansion.
    ///   - fileManager:    Allows injection of a custom `FileManager` for testing.
    public init(
        commands: [SlashCommand] = [],
        staticCommands: [AutocompleteItem] = [],
        basePath: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) {
        self.commands = commands
        self.staticCommands = staticCommands
        self.baseURL = URL(fileURLWithPath: basePath)
        self.fileManager = fileManager
    }

    // MARK: - AutocompleteProvider

    public func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> AutocompleteSuggestion? {
        guard lines.indices.contains(cursorLine) else { return nil }
        let currentLine = lines[cursorLine]
        let colClamped = min(cursorCol, currentLine.count)
        let prefixIdx = currentLine.index(currentLine.startIndex, offsetBy: colClamped)
        let beforeCursor = String(currentLine[..<prefixIdx])

        // Slash commands
        if beforeCursor.hasPrefix("/") {
            return slashCommandSuggestions(textBeforeCursor: beforeCursor)
        }

        // File / @mention paths
        if let ctx = extractPathPrefix(from: beforeCursor, force: false) {
            let items = fileSuggestions(for: ctx)
            if !items.isEmpty { return AutocompleteSuggestion(items: items, prefix: ctx.token) }
        }

        return nil
    }

    public func forceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> AutocompleteSuggestion? {
        guard lines.indices.contains(cursorLine) else { return nil }
        let currentLine = lines[cursorLine]
        let colClamped = min(cursorCol, currentLine.count)
        let prefixIdx = currentLine.index(currentLine.startIndex, offsetBy: colClamped)
        let beforeCursor = String(currentLine[..<prefixIdx])
        guard let ctx = extractPathPrefix(from: beforeCursor, force: true) else { return nil }
        let items = fileSuggestions(for: ctx)
        guard !items.isEmpty else { return nil }
        return AutocompleteSuggestion(items: items, prefix: ctx.token)
    }

    public func shouldTriggerFileCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> Bool {
        guard lines.indices.contains(cursorLine) else { return true }
        let currentLine = lines[cursorLine]
        let colClamped = min(cursorCol, currentLine.count)
        let prefixIdx = currentLine.index(currentLine.startIndex, offsetBy: colClamped)
        let beforeCursor = String(currentLine[..<prefixIdx])
        // Suppress file completion when inside a slash-command name (no space yet).
        if beforeCursor.hasPrefix("/"), !beforeCursor.contains(" ") { return false }
        return true
    }

    // MARK: - Slash command matching

    private func slashCommandSuggestions(textBeforeCursor: String) -> AutocompleteSuggestion? {
        if let spaceIdx = textBeforeCursor.firstIndex(of: " ") {
            // Already past the command name → complete arguments.
            let cmdName = String(
                textBeforeCursor[textBeforeCursor.index(after: textBeforeCursor.startIndex)..<spaceIdx])
            guard let command = commands.first(where: { $0.name == cmdName }) else { return nil }
            let argText = String(textBeforeCursor[textBeforeCursor.index(after: spaceIdx)...])
            let items = command.argumentCompletions(prefix: argText)
            return items.isEmpty ? nil : AutocompleteSuggestion(items: items, prefix: argText)
        } else {
            // Still typing the command name → filter commands.
            let prefixText = String(textBeforeCursor.dropFirst()) // drop leading /
            var items: [AutocompleteItem] = []

            for command in commands where command.name.lowercased().hasPrefix(prefixText.lowercased()) {
                if command.expandsInlineWhenNoArg {
                    // Expand argument completions inline, rewriting item values to the
                    // full "/name arg" form so applyCompletion inserts the whole command.
                    let expanded = command.argumentCompletions(prefix: "").map {
                        AutocompleteItem(
                            value: command.name + " " + $0.value,
                            label: $0.label,
                            description: $0.description
                        )
                    }
                    items.append(contentsOf: expanded)
                } else {
                    items.append(AutocompleteItem(
                        value: command.name,
                        label: "/" + command.name,
                        description: command.description
                    ))
                }
            }

            let inlineMatches = staticCommands.filter {
                $0.value.lowercased().hasPrefix(prefixText.lowercased())
            }
            // Ensure static-command labels also have a leading "/" for display.
            let labelledInline = inlineMatches.map {
                let label = $0.label.hasPrefix("/") ? $0.label : "/" + $0.label
                return AutocompleteItem(value: $0.value, label: label, description: $0.description)
            }
            items.append(contentsOf: labelledInline)
            return items.isEmpty ? nil : AutocompleteSuggestion(items: items, prefix: textBeforeCursor)
        }
    }

    // MARK: - File path matching

    private struct PathContext {
        let token: String
        let isAttachment: Bool
        let forced: Bool
    }

    private func extractPathPrefix(from text: String, force: Bool) -> PathContext? {
        let fullRange = NSRange(location: 0, length: text.utf16.count)

        // @mention first
        if let regex = attachmentRegex,
           let match = regex.firstMatch(in: text, options: [], range: fullRange),
           let range = Range(match.range, in: text)
        {
            return PathContext(token: String(text[range]), isAttachment: true, forced: force)
        }

        // Path token
        if let regex = pathRegex,
           let match = regex.firstMatch(in: text, options: [], range: fullRange),
           let captureRange = Range(match.range(at: 1), in: text)
        {
            let token = String(text[captureRange])
            if token.isEmpty, !force { return nil }
            if token.contains("/") || token.hasPrefix(".") || token.hasPrefix("~") {
                return PathContext(token: token, isAttachment: false, forced: force)
            }
            if force { return PathContext(token: token, isAttachment: false, forced: true) }
            return nil
        }

        return force ? PathContext(token: "", isAttachment: false, forced: true) : nil
    }

    private func fileSuggestions(for context: PathContext) -> [AutocompleteItem] {
        let baseToken = context.isAttachment ? String(context.token.dropFirst()) : context.token
        let resolved = resolvePath(baseToken)
        let directoryURL: URL
        let searchPrefix: String

        if baseToken.isEmpty || baseToken.hasSuffix("/") {
            directoryURL = resolved
            searchPrefix = ""
        } else {
            directoryURL = resolved.deletingLastPathComponent()
            searchPrefix = resolved.lastPathComponent
        }

        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        guard let cachedEntries = listDirectory(directoryURL) else { return [] }

        var items: [AutocompleteItem] = []
        for entry in cachedEntries {
            let name = entry.name
            let bypassPrefix = context.forced && searchPrefix.isEmpty
            if !bypassPrefix, !name.lowercased().hasPrefix(searchPrefix.lowercased()) { continue }
            let isDirectory = entry.isDirectory
            if context.isAttachment, !isDirectory,
               !isAttachable(url: directoryURL.appendingPathComponent(name)) { continue }
            let valuePath = buildCompletionPath(
                typedToken: baseToken, component: name, isDirectory: isDirectory, context: context)
            items.append(AutocompleteItem(
                value: valuePath,
                label: name + (isDirectory ? "/" : ""),
                description: isDirectory ? "directory" : "file"))
        }
        return items
            .sorted {
                let lDir = $0.description == "directory"
                let rDir = $1.description == "directory"
                if lDir != rDir { return lDir }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            .prefix(10)
            .map(\.self)
    }

    private func resolvePath(_ typed: String) -> URL {
        if typed.hasPrefix("/") { return URL(fileURLWithPath: typed).standardizedFileURL }
        if typed.hasPrefix("~") {
            let home = fileManager.homeDirectoryForCurrentUser
            return home.appendingPathComponent(String(typed.dropFirst()))
        }
        if typed.isEmpty { return baseURL }
        return baseURL.appendingPathComponent(typed)
    }

    private func buildCompletionPath(
        typedToken: String,
        component: String,
        isDirectory: Bool,
        context: PathContext
    ) -> String {
        var base = typedToken
        if base.isEmpty || base.hasSuffix("/") {
            base += component
        } else {
            let parent = (base as NSString).deletingLastPathComponent
            base = parent.isEmpty ? component : parent + "/" + component
        }
        let completed = base + (isDirectory ? "/" : "")
        return completed
    }

    // MARK: - Attachment filter

    private static let attachableExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "kt", "java",
        "c", "cpp", "h", "hpp", "cs", "m", "mm", "sh", "bash", "zsh",
        "json", "yaml", "yml", "toml", "xml", "plist", "graphql", "sql",
        "md", "txt", "log", "csv",
        "html", "css", "scss", "sass",
        "dockerfile", "makefile", "rakefile", "podfile", "gemfile",
        "env", "gitignore", "gitattributes", "editorconfig",
        // Image attachments (handled by vision-enabled hosts).
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp",
    ]

    private func isAttachable(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.attachableExtensions.contains(ext)
    }
}
