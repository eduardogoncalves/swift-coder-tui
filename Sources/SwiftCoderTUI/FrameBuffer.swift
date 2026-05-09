// MARK: - Cell

/// A single terminal cell with a character and ANSI styling attributes.
public struct Cell: Equatable, Sendable {
    /// The character displayed in this cell. Defaults to a space.
    public var character: Character
    /// Optional foreground color. `nil` means "terminal default".
    public var foreground: Color?
    /// Optional background color. `nil` means "terminal default".
    public var background: Color?
    /// Bold (SGR 1).
    public var bold: Bool
    /// Italic (SGR 3).
    public var italic: Bool
    /// Underline (SGR 4).
    public var underline: Bool
    /// `true` when this cell occupies two terminal columns (East-Asian wide char).
    public var isWide: Bool
    /// `true` when this cell is the right-hand continuation column of a wide character.
    /// `render()` skips continuation cells; they exist only to mark occupied columns.
    public var isContinuation: Bool

    public init(
        character: Character = " ",
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        isWide: Bool = false,
        isContinuation: Bool = false
    ) {
        self.character = character
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.isWide = isWide
        self.isContinuation = isContinuation
    }

    /// A blank cell with no styling — the canonical "empty" sentinel.
    public static let empty = Cell()
}

// MARK: - FrameBuffer

/// A cell-based framebuffer that supports multiple-layer compositing and ANSI rendering.
///
/// Usage sketch:
/// ```swift
/// var fb = FrameBuffer(width: 80, height: 24)
/// fb.writeText("Hello", x: 0, y: 0, foreground: .ansi(.green))
///
/// var overlay = FrameBuffer(width: 20, height: 3)
/// overlay.fill(rect: (x: 0, y: 0, w: 20, h: 3), cell: Cell(background: .ansi(.blue)))
/// fb.overlay(overlay, at: 10, y: 5)
///
/// print(fb.render())
/// ```
public struct FrameBuffer {

    // MARK: - Storage

    public let width: Int
    public let height: Int
    /// Row-major flat storage: `cells[y * width + x]`.
    private var cells: [Cell]

    // MARK: - Init

    public init(width: Int, height: Int, fill: Cell = .empty) {
        precondition(width > 0 && height > 0, "FrameBuffer dimensions must be positive")
        self.width = width
        self.height = height
        self.cells = Array(repeating: fill, count: width * height)
    }

    // MARK: - Subscript

    /// Accesses the cell at column `x`, row `y` (both zero-based).
    /// Out-of-bounds reads return `.empty`; out-of-bounds writes are no-ops.
    public subscript(x: Int, y: Int) -> Cell {
        get {
            guard isValid(x: x, y: y) else { return .empty }
            return cells[y * width + x]
        }
        set {
            guard isValid(x: x, y: y) else { return }
            cells[y * width + x] = newValue
        }
    }

    // MARK: - Mutation

    /// Fills the entire buffer with `cell` (default `.empty`).
    public mutating func clear(with cell: Cell = .empty) {
        cells = Array(repeating: cell, count: width * height)
    }

    /// Writes `text` into the buffer starting at column `x`, row `y`.
    ///
    /// - Any ANSI escape sequences embedded in `text` are stripped before rendering.
    /// - East-Asian wide characters occupy two columns: the primary cell has `isWide = true`
    ///   and the following column gets a continuation cell.
    /// - Text is clipped at the right edge; it never wraps to the next line.
    /// - Styling precedence: explicit `foreground`/`background` parameters override colors
    ///   derived from `attributes`; bold/italic/underline come from `attributes` only.
    public mutating func writeText(
        _ text: String,
        x: Int,
        y: Int,
        attributes: TextAttributes? = nil,
        foreground: Color? = nil,
        background: Color? = nil
    ) {
        guard y >= 0 && y < height else { return }

        // Read attribute fields directly through TextAttributes' public
        // accessors instead of round-tripping through `openSequence` and
        // re-parsing it.
        let bold      = attributes?.isBold      ?? false
        let italic    = attributes?.isItalic    ?? false
        let underline = attributes?.isUnderline ?? false
        let fg        = foreground ?? attributes?.foregroundColor
        let bg        = background ?? attributes?.backgroundColor

        // Strip any embedded ANSI so we only measure and store raw characters.
        let plain = VisibleWidth.stripAnsi(text)

        var curX = x
        for char in plain {
            guard curX < width else { break }
            let w = VisibleWidth.measure(String(char))
            guard w > 0 else { continue }   // skip zero-width/combining characters
            guard curX >= 0 else { curX += w; continue }   // skip negative-offset chars

            // Skip a wide char that would overflow the right edge.
            if w == 2 && curX + 1 >= width { break }

            self[curX, y] = Cell(
                character: char,
                foreground: fg,
                background: bg,
                bold: bold,
                italic: italic,
                underline: underline,
                isWide: w == 2
            )

            if w == 2 {
                // Continuation cell inherits background so the two columns look uniform.
                self[curX + 1, y] = Cell(
                    character: " ",
                    foreground: fg,
                    background: bg,
                    isContinuation: true
                )
            }

            curX += w
        }
    }

    /// Fills every cell inside `rect` with `cell`.
    /// Coordinates outside the buffer are silently clamped/ignored.
    public mutating func fill(rect: (x: Int, y: Int, w: Int, h: Int), cell: Cell) {
        let xEnd = min(rect.x + rect.w, width)
        let yEnd = min(rect.y + rect.h, height)
        let xStart = max(rect.x, 0)
        let yStart = max(rect.y, 0)
        guard xStart < xEnd && yStart < yEnd else { return }
        for row in yStart..<yEnd {
            for col in xStart..<xEnd {
                cells[row * width + col] = cell
            }
        }
    }

    /// Composites `other` on top of `self` with its origin at `(x, y)`.
    ///
    /// - Parameter transparent: If non-nil, cells in `other` that equal this value are
    ///   skipped, preserving whatever was in `self` at that position.
    public mutating func overlay(_ other: FrameBuffer, at x: Int, y: Int, transparent: Cell? = nil) {
        for oy in 0..<other.height {
            for ox in 0..<other.width {
                let cell = other[ox, oy]
                if let sentinel = transparent, cell == sentinel { continue }
                self[x + ox, y + oy] = cell
            }
        }
    }

    // MARK: - Rendering

    /// Renders the buffer to a single ANSI escape string.
    ///
    /// The output:
    /// - Begins with `ESC[0m` (reset) then positions the cursor at row 1, col 1 via `ESC[H`.
    /// - Positions the cursor at the start of each subsequent row with `ESC[{row+1};1H`.
    /// - Emits SGR attribute-change sequences **only on transitions** between cells
    ///   (i.e. minimal diffs, not per-cell).
    /// - Ends with `ESC[0m` to reset styling.
    public func render() -> String {
        var out = ""
        out.reserveCapacity(width * height * 6)

        // Reset then home.
        out += "\u{1B}[0m\u{1B}[H"

        var current = CellStyle.empty

        for row in 0..<height {
            if row > 0 {
                // Absolute-position each row so rendering is independent of column width.
                out += "\u{1B}[\(row + 1);1H"
            }

            for col in 0..<width {
                let cell = cells[row * width + col]

                // Continuation cells occupy a column but produce no output character.
                if cell.isContinuation { continue }

                let next = CellStyle(cell)

                if next != current {
                    out += next.resetEncodedSequence()
                    current = next
                }

                out.append(cell.character)
            }
        }

        out += "\u{1B}[0m"
        return out
    }

    // MARK: - Private helpers

    private func isValid(x: Int, y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }
}
