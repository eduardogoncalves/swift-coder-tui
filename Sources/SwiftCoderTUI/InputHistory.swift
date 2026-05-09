import Foundation

// MARK: - InputHistory

/// Ordered command-history store with cursor-based navigation, matching the
/// Up/Down behaviour of interactive shells (bash, zsh).
///
/// ```swift
/// let history = InputHistory()
/// history.add("ls -la")
/// history.add("swift build")
///
/// history.previous() // → "swift build"
/// history.previous() // → "ls -la"
/// history.previous() // → "ls -la"  (clamped at oldest)
/// history.next()     // → "swift build"
/// history.next()     // → nil        (past newest → back to draft)
/// ```
public final class InputHistory {

    // MARK: Stored state

    private var _entries: [String] = []
    private let capacity: Int

    /// Index into `_entries` for the current navigation position.
    /// `_entries.count` means "past the newest entry" (at the live draft).
    private var cursor: Int

    // MARK: Init

    public init(capacity: Int = 1000) {
        self.capacity = max(1, capacity)
        self.cursor = 0
        _entries.reserveCapacity(self.capacity)
    }

    // MARK: Public read-only view

    /// All stored history entries, oldest first.
    public var entries: [String] { _entries }

    /// `true` when the cursor has been moved backward (i.e. the user has pressed ↑
    /// at least once since the last ``resetCursor()`` call).  Use this to distinguish
    /// "navigating back to the live draft" from "never entered history navigation".
    public var isNavigating: Bool { cursor < _entries.count }

    // MARK: Mutation

    /// Appends `entry` to history.
    ///
    /// - Empty strings are ignored.
    /// - Consecutive duplicates are deduplicated (only the latest copy is kept).
    /// - When the store is full the oldest entry is evicted.
    public func add(_ entry: String) {
        guard !entry.isEmpty else { return }
        if _entries.last == entry { return }
        if _entries.count >= capacity {
            // Drop the oldest 10% in one O(k) shift instead of an O(n) shift on
            // every single insert — amortizes eviction over many calls when the
            // history is full.
            let dropCount = max(1, capacity / 10)
            _entries.removeFirst(dropCount)
        }
        _entries.append(entry)
    }

    /// Move the navigation cursor one step toward older entries and return the
    /// entry there.  Clamps at the oldest entry (never returns `nil`).
    ///
    /// Returns `nil` only when the history is empty.
    public func previous() -> String? {
        guard !_entries.isEmpty else { return nil }
        if cursor > 0 { cursor -= 1 }
        return _entries[cursor]
    }

    /// Move the navigation cursor one step toward newer entries and return the
    /// entry there.  Returns `nil` when the cursor moves past the newest entry
    /// (signalling "back to the live draft").
    public func next() -> String? {
        guard cursor < _entries.count else { return nil }
        cursor += 1
        guard cursor < _entries.count else { return nil }
        return _entries[cursor]
    }

    /// Reset the navigation cursor to "past newest" so the next ``previous()``
    /// call starts from the most recent entry.  Call this whenever the user
    /// submits a line or begins fresh editing.
    public func resetCursor() {
        cursor = _entries.count
    }

    // MARK: Optional search

    /// Returns all entries whose prefix matches `prefix` (case-sensitive),
    /// ordered oldest-first.
    public func search(prefix: String) -> [String] {
        guard !prefix.isEmpty else { return _entries }
        return _entries.filter { $0.hasPrefix(prefix) }
    }
}
