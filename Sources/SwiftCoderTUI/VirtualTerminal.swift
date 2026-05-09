/// An in-memory ``Terminal`` implementation that accumulates all output in a `String`
/// buffer rather than writing to a real TTY.  Useful for snapshot tests and headless
/// rendering pipelines.
public final class VirtualTerminal: Terminal, @unchecked Sendable {

    // MARK: - Size

    public private(set) var rows: Int
    public private(set) var cols: Int

    // MARK: - Buffer

    private var buffer: String = ""
    private var frameBuffer: String = ""
    private var inFrame: Bool = false

    /// The accumulated output written through this terminal.
    public var output: String { buffer }

    // MARK: - Init

    public init(rows: Int = 24, cols: Int = 80) {
        self.rows = rows
        self.cols = cols
    }

    // MARK: - Buffer helpers

    /// Resets the accumulated output to an empty string.
    public func clearOutput() {
        buffer = ""
    }

    // MARK: - Terminal: write

    public func write(_ s: String) {
        if inFrame {
            frameBuffer.append(s)
        } else {
            buffer.append(s)
        }
    }

    // MARK: - Terminal: cursor / screen

    public func moveTo(row: Int, col: Int) {
        write(EscapeSequence.moveTo(row: row, col: col))
    }

    public func clearLine() {
        write(EscapeSequence.clearLine())
    }

    public func clearToEndOfLine() {
        write("\u{001B}[K")
    }

    public func clearScreen() {
        write("\u{001B}[2J")
    }

    public func hideCursor() {
        write(EscapeSequence.hideCursor())
    }

    public func showCursor() {
        write(EscapeSequence.showCursor())
    }

    // MARK: - Terminal: frame buffering

    public func beginFrame() {
        inFrame = true
        frameBuffer.removeAll(keepingCapacity: true)
    }

    public func endFrame() {
        inFrame = false
        buffer.append(frameBuffer)
        frameBuffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Terminal: lifecycle (no-ops in virtual terminal)

    public func setupRawMode(title: String) {}
    public func restoreMode() {}
    public func setTitle(_ title: String) {}
    public func updateSize() {}
    public func setBracketedPaste(enabled: Bool) {}
}
