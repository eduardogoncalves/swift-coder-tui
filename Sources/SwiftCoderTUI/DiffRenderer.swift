// DiffRenderer.swift
//
// Differential cell-buffer renderer for **viewport-pinned** TUI layouts.
//
// This renderer is designed for UIs that own the full terminal viewport and
// repaint it with absolute cursor addressing (ESC[row;colH).  It is NOT used
// by the default ``Renderer`` actor, which uses a *scrollback* model where
// content flows into the terminal's own scrollback buffer and only the footer
// block is redrawn with relative cursor moves (ESC[nA / ESC[nB).
//
// Use ``DiffRenderer`` if you are building a full-screen TUI on top of
// ``FrameBuffer``; use ``Renderer`` for the standard chat/streaming layout.
//
// SGR state is represented by the shared ``CellStyle`` type defined in
// `SGR.swift`. Unlike `FrameBuffer.render()` — which takes the safe path of
// emitting `ESC[0m` then re-applying every active attribute on every change —
// `DiffRenderer` minimises traffic by diffing each attribute individually and
// only resetting when an attribute must be turned off (SGR has no per-flag
// "un-bold" code).
//
// Adaptation note: Cell has `isContinuation: Bool` in addition to `isWide: Bool`.
// Continuation cells are skipped in output (they mark the right-half column of a
// wide char).  Cursor-advance for wide characters is 2 columns.

// MARK: - DiffRenderer

/// A stateless differential renderer that compares two ``FrameBuffer`` snapshots and emits
/// the minimum ANSI escape sequence needed to update the terminal display.
public enum DiffRenderer {

    /// Returns the ANSI string that updates the terminal from `previous` to `current`.
    ///
    /// - If `previous` is `nil` or the buffer dimensions differ, a full repaint is emitted:
    ///   `ESC[2J ESC[H` followed by the entire current buffer.
    /// - Otherwise only changed cells are written; cursor jumps skip unchanged spans.
    ///
    /// The returned string always ends with `ESC[0m` to reset SGR.
    public static func render(previous: FrameBuffer?, current: FrameBuffer) -> String {
        var output = String()
        output.reserveCapacity(current.width * current.height * 8)

        guard let prev = previous,
              prev.width == current.width,
              prev.height == current.height else {
            appendFullRender(to: &output, buffer: current)
            return output
        }

        appendDiffRender(to: &output, previous: prev, current: current)
        return output
    }

    // MARK: - Full render

    private static func appendFullRender(to out: inout String, buffer: FrameBuffer) {
        // Clear screen and move cursor to top-left (1;1 in ANSI 1-based coords).
        out += "\u{1B}[2J\u{1B}[H"

        var state = CellStyle.empty

        for y in 0..<buffer.height {
            // Move to the start of each row explicitly; this handles row transitions
            // correctly even after wide characters shift the column count.
            out += "\u{1B}[\(y + 1);1H"
            for x in 0..<buffer.width {
                let cell = buffer[x, y]
                // Continuation cells mark the right-half column of a wide character;
                // the wide character itself already occupied that space visually.
                if cell.isContinuation { continue }
                appendSGRTransition(to: &out, from: state, to: CellStyle(cell), state: &state)
                out.append(cell.character)
            }
        }

        out += SGR.reset
    }

    // MARK: - Diff render

    private static func appendDiffRender(
        to out: inout String,
        previous: FrameBuffer,
        current: FrameBuffer
    ) {
        var state = CellStyle.empty
        // Track logical cursor position (0-based) so we can elide redundant moves.
        var curX = 0
        var curY = 0
        var cursorPositioned = false

        for y in 0..<current.height {
            for x in 0..<current.width {
                let cell = current[x, y]
                // Skip continuation cells — they produce no output.
                if cell.isContinuation { continue }

                let prev = previous[x, y]
                let advance = cell.isWide ? 2 : 1

                // Unchanged cell — skip; cursor will be repositioned on next dirty cell.
                guard cell != prev else {
                    continue
                }

                // Position the cursor only when it isn't already at (x, y).
                // ANSI cursor addresses are 1-based.
                if !cursorPositioned || curX != x || curY != y {
                    out += "\u{1B}[\(y + 1);\(x + 1)H"
                    curX = x
                    curY = y
                    cursorPositioned = true
                }

                appendSGRTransition(to: &out, from: state, to: CellStyle(cell), state: &state)
                out.append(cell.character)
                // After writing, the terminal cursor has advanced by `advance` columns.
                curX += advance
            }
        }

        out += SGR.reset
    }

    // MARK: - SGR helpers

    /// Emits the minimal SGR sequences to transition the terminal from `current` attributes
    /// to `next` attributes, updating `state` in place.
    private static func appendSGRTransition(
        to out: inout String,
        from current: CellStyle,
        to next: CellStyle,
        state: inout CellStyle
    ) {
        guard current != next else { return }

        // A full reset is required when an active attribute must be turned off,
        // because SGR has no individual "un-bold" or "un-italic" code.
        let needsReset = (current.bold && !next.bold)
            || (current.italic && !next.italic)
            || (current.underline && !next.underline)
            || (current.foreground != nil && next.foreground == nil)
            || (current.background != nil && next.background == nil)

        if needsReset {
            out += SGR.reset
            state = CellStyle.empty
        }

        // Batch bold / italic / underline into a single CSI sequence.
        var params: [String] = []
        if next.bold && !state.bold           { params.append("1") }
        if next.italic && !state.italic       { params.append("3") }
        if next.underline && !state.underline { params.append("4") }

        if !params.isEmpty {
            out += SGR.encode(params)
            state.bold = next.bold
            state.italic = next.italic
            state.underline = next.underline
        }

        // Foreground color.
        if next.foreground != state.foreground {
            if let fg = next.foreground {
                out += fg.foregroundSGR
            } else {
                out += Color.resetForeground
            }
            state.foreground = next.foreground
        }

        // Background color.
        if next.background != state.background {
            if let bg = next.background {
                out += bg.backgroundSGR
            } else {
                out += Color.resetBackground
            }
            state.background = next.background
        }
    }
}
