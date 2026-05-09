import Foundation

// MARK: - EditorAction

/// The semantic result returned by ``LineEditor/handle(key:)``.
///
/// Inspect this value to decide whether and how to redraw your UI after a
/// keystroke.
public enum EditorAction: Equatable {
    /// A character or paste was inserted into the buffer.
    case inserted
    /// The cursor moved without changing the text.
    case cursorMoved
    /// One or more characters were deleted.
    case deleted
    /// The user submitted the current line (``Keystroke/enter``).
    case submit
    /// ``Keystroke/ctrlL`` — the caller should clear the terminal screen and redraw.
    case clearScreen
    /// The key was not handled by the editor (e.g. an arrow key the caller
    /// wants to use for selection or scrolling).
    case none
}

// MARK: - LineEditor

/// Single-line editing buffer with Readline-style keyboard shortcuts and
/// optional shell-style history navigation.
///
/// Maintain one `LineEditor` per text field. Feed ``Keystroke`` values from
/// ``InputHandler/keystrokes()`` into ``handle(key:)``, then read ``text``
/// and ``cursorOffset`` to update your UI.
///
/// ```swift
/// var editor = LineEditor()
/// editor.history = InputHistory()
/// for await key in InputHandler.keystrokes() {
///     let action = editor.handle(key: key)
///     if action == .submit { sendMessage(editor.text); editor.clear() }
///     redraw(text: editor.text, cursor: editor.cursorOffset)
/// }
/// ```
///
/// ## Readline shortcuts
///
/// | Key    | Action                                    |
/// |--------|-------------------------------------------|
/// | Ctrl+A | Move cursor to beginning of line          |
/// | Ctrl+E | Move cursor to end of line                |
/// | Ctrl+U | Delete from cursor to start of line       |
/// | Ctrl+K | Delete from cursor to end of line         |
/// | Ctrl+W | Delete previous whitespace-delimited word |
/// | Ctrl+L | Signal caller to clear the screen         |
public struct LineEditor {

    // MARK: Public state

    /// Current text content of the line buffer.
    public private(set) var text: String = ""

    /// `String.Index` pointing to the insertion point within ``text``.
    public private(set) var cursorIndex: String.Index

    /// Number of ``Character`` values before the cursor (zero-based column).
    public var cursorOffset: Int {
        text.distance(from: text.startIndex, to: cursorIndex)
    }

    /// Optional history store.  Assign a shared ``InputHistory`` instance to
    /// enable Up/Down arrow history navigation.
    public var history: InputHistory?

    /// Saved draft text while the user browses history.  Restored when Down
    /// arrow moves past the newest history entry.
    private var savedDraft: String?

    // MARK: Init

    public init() {
        cursorIndex = "".startIndex
    }

    // MARK: Public API

    /// Process a single keystroke and update the buffer.
    ///
    /// - Returns: The semantic ``EditorAction`` that occurred.
    @discardableResult
    public mutating func handle(key: Keystroke) -> EditorAction {
        switch key {

        // MARK: Insert
        case .character(let ch):
            history?.resetCursor()
            savedDraft = nil
            let newOffset = cursorOffset + 1
            text.insert(ch, at: cursorIndex)
            cursorIndex = text.index(text.startIndex, offsetBy: newOffset)
            return .inserted

        case .paste(let str):
            guard !str.isEmpty else { return .none }
            history?.resetCursor()
            savedDraft = nil
            let newOffset = cursorOffset + str.count
            text.insert(contentsOf: str, at: cursorIndex)
            cursorIndex = text.index(text.startIndex, offsetBy: newOffset)
            return .inserted

        // MARK: Delete
        case .backspace:
            guard cursorIndex > text.startIndex else { return .none }
            let prev = text.index(before: cursorIndex)
            text.remove(at: prev)
            cursorIndex = prev
            return .deleted

        case .delete:
            guard cursorIndex < text.endIndex else { return .none }
            text.remove(at: cursorIndex)
            return .deleted

        // MARK: Cursor movement
        case .arrowLeft:
            guard cursorIndex > text.startIndex else { return .none }
            cursorIndex = text.index(before: cursorIndex)
            return .cursorMoved

        case .arrowRight:
            guard cursorIndex < text.endIndex else { return .none }
            cursorIndex = text.index(after: cursorIndex)
            return .cursorMoved

        case .arrowUp:
            guard let hist = history else { return .none }
            if savedDraft == nil { savedDraft = text }
            guard let entry = hist.previous() else { return .none }
            set(text: entry)
            return .cursorMoved

        case .arrowDown:
            guard let hist = history else { return .none }
            if let entry = hist.next() {
                set(text: entry)
            } else {
                set(text: savedDraft ?? "")
                savedDraft = nil
            }
            return .cursorMoved

        // MARK: Readline: beginning / end of line
        case .ctrlA:
            guard cursorIndex != text.startIndex else { return .none }
            cursorIndex = text.startIndex
            return .cursorMoved

        case .ctrlE:
            guard cursorIndex != text.endIndex else { return .none }
            cursorIndex = text.endIndex
            return .cursorMoved

        // MARK: Readline: kill to start / end
        case .ctrlU:
            guard cursorIndex > text.startIndex else { return .none }
            text.removeSubrange(text.startIndex..<cursorIndex)
            cursorIndex = text.startIndex
            return .deleted

        case .ctrlK:
            guard cursorIndex < text.endIndex else { return .none }
            text.removeSubrange(cursorIndex..<text.endIndex)
            // cursorIndex is now at endIndex (the new endIndex after removal)
            return .deleted

        // MARK: Readline: kill previous word
        case .ctrlW:
            return deleteWordBackward()

        // MARK: Readline: clear screen signal
        case .ctrlL:
            return .clearScreen

        // MARK: Submit
        case .enter:
            history?.add(text)
            history?.resetCursor()
            savedDraft = nil
            return .submit

        default:
            return .none
        }
    }

    /// Replace the entire buffer with `newText` and place the cursor at
    /// `cursorOffset` characters from the start (clamped to text bounds).
    public mutating func setText(_ newText: String, cursorOffset: Int) {
        text = newText
        let clamped = max(0, min(cursorOffset, text.count))
        cursorIndex = text.index(text.startIndex, offsetBy: clamped)
    }

    /// Move the cursor to the given character offset, clamped to text bounds.
    public mutating func setCursor(offset: Int) {
        let clamped = max(0, min(offset, text.count))
        cursorIndex = text.index(text.startIndex, offsetBy: clamped)
    }

    /// Replace the entire buffer with `newText` and move the cursor to the end.
    public mutating func set(text newText: String) {
        text = newText
        cursorIndex = text.endIndex
    }

    /// Clear the buffer and reset the cursor to the start.
    public mutating func clear() {
        text = ""
        cursorIndex = text.startIndex
    }

    // MARK: - Private helpers

    /// Delete backward from the cursor to the start of the previous word.
    ///
    /// "Word" is whitespace-delimited (matches Bash / Readline behaviour).
    private mutating func deleteWordBackward() -> EditorAction {
        guard cursorIndex > text.startIndex else { return .none }
        var idx = cursorIndex
        // Skip any trailing whitespace before the cursor.
        while idx > text.startIndex {
            let prev = text.index(before: idx)
            if text[prev].isWhitespace { idx = prev } else { break }
        }
        guard idx > text.startIndex else {
            text.removeSubrange(text.startIndex..<cursorIndex)
            cursorIndex = text.startIndex
            return .deleted
        }
        // Walk back over non-whitespace.
        while idx > text.startIndex {
            let prev = text.index(before: idx)
            if text[prev].isWhitespace { break }
            idx = prev
        }
        text.removeSubrange(idx..<cursorIndex)
        cursorIndex = idx
        return .deleted
    }
}
