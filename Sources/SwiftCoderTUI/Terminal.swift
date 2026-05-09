#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

// MARK: - ANSI Escape Sequence Generators

/// Pure-utility namespace for ANSI/VT100 escape sequence strings.
/// These functions return strings and perform no I/O.
public enum EscapeSequence {
    public static let esc = "\u{001B}["

    public static func moveTo(row: Int, col: Int) -> String {
        "\u{001B}[\(row);\(col)H"
    }

    public static func clearLine() -> String { "\u{001B}[2K" }

    public static func clearToEnd() -> String { "\u{001B}[0J" }

    public static func saveCursor() -> String { "\u{001B}[s" }

    public static func restoreCursor() -> String { "\u{001B}[u" }

    public static func hideCursor() -> String { "\u{001B}[?25l" }

    public static func showCursor() -> String { "\u{001B}[?25h" }

    public static func scrollRegion(top: Int, bottom: Int) -> String {
        "\u{001B}[\(top);\(bottom)r"
    }

    public static func resetScrollRegion() -> String { "\u{001B}[r" }
}

// MARK: - Terminal Protocol

public protocol Terminal: AnyObject {
    var rows: Int { get }
    var cols: Int { get }

    func write(_ s: String)
    func moveTo(row: Int, col: Int)
    func clearLine()
    func clearToEndOfLine()
    func clearScreen()
    func hideCursor()
    func showCursor()

    func setupRawMode(title: String)
    func restoreMode()
    func setTitle(_ title: String)
    func updateSize()

    // Frame buffering — batch all writes in a redraw into one syscall (Wave 2).
    func beginFrame()
    func endFrame()

    /// Enable or disable the terminal's bracketed-paste mode.
    ///
    /// When enabled the terminal wraps pasted text in `ESC[200~` … `ESC[201~`
    /// markers so ``InputHandler`` can deliver it as a single ``Keystroke/paste(_:)``
    /// event instead of individual character keystrokes.
    func setBracketedPaste(enabled: Bool)
}

// MARK: - ProcessTerminal

/// Concrete `Terminal` backed by the real TTY (stdout / POSIX write).
public final class ProcessTerminal: Terminal, @unchecked Sendable {

    private var originalTermios = termios()

    public private(set) var rows: Int = 24
    public private(set) var cols: Int = 80

    // MARK: Frame buffering

    private var frameBuffer: String = ""
    private var inFrame: Bool = false

    // MARK: Init

    public init() {
        updateSize()
    }

    // MARK: - Size

    public func updateSize() {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 {
            rows = Int(ws.ws_row)
            cols = Int(ws.ws_col)
        }
    }

    // MARK: - Raw mode lifecycle

    public func setupRawMode(title: String) {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        // Disable echo, canonical mode, signals, and extended processing
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG | IEXTEN)
        // Disable CR-to-NL, flow control
        raw.c_iflag &= ~UInt(ICRNL | IXON)
        // Disable output post-processing
        raw.c_oflag &= ~UInt(OPOST)
        // Read returns after 1 byte, no timeout.
        // Use the platform-supplied VMIN/VTIME indices because their numeric
        // values differ between Darwin (16/17) and Linux glibc (6/5); the
        // previous hardcoded `c_cc.16/.17` clobbered VEOF/VEOL on Linux.
        withUnsafeMutablePointer(to: &raw.c_cc) { tuplePtr in
            tuplePtr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { p in
                p[Int(VMIN)] = 1
                p[Int(VTIME)] = 0
            }
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        setTitle(title)
        // Request Kitty keyboard protocol (flag 1 = disambiguate escape codes).
        write("\u{001B}[>1u")
    }

    public func restoreMode() {
        // Pop Kitty keyboard protocol flags we pushed on setup
        write("\u{001B}[<u")
        write(EscapeSequence.showCursor())
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }

    public func setTitle(_ title: String) {
        write("\u{001B}]0;\(title)\u{0007}")
    }

    // MARK: - Cursor / Screen helpers

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

    // MARK: - Bracketed paste

    public func setBracketedPaste(enabled: Bool) {
        write(enabled ? "\u{001B}[?2004h" : "\u{001B}[?2004l")
    }

    // MARK: - Frame buffering

    public func beginFrame() {
        inFrame = true
        frameBuffer.removeAll(keepingCapacity: true)
        frameBuffer.reserveCapacity(16384)
        // CSI 2026: synchronized output mode begin — terminals that don't support
        // this private mode simply ignore it, so it is safe on all terminals.
        frameBuffer.append("\u{001B}[?2026h")
    }

    public func endFrame() {
        inFrame = false
        // CSI 2026: synchronized output mode end — emit before the single flush.
        frameBuffer.append("\u{001B}[?2026l")
        if !frameBuffer.isEmpty {
            rawWrite(frameBuffer)
            frameBuffer.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - Write

    public func write(_ s: String) {
        if inFrame { frameBuffer.append(s) } else { rawWrite(s) }
    }

    private func rawWrite(_ s: String) {
        // Iterate UTF-8 bytes directly without an extra strlen pass on a
        // throwaway C string copy of the entire frame.
        var copy = s
        copy.withUTF8 { buf in
            guard let base = buf.baseAddress else { return }
            let total = buf.count
            var written = 0
            while written < total {
                #if canImport(Darwin)
                let r = Darwin.write(STDOUT_FILENO, base + written, total - written)
                #elseif canImport(Glibc)
                let r = Glibc.write(STDOUT_FILENO, base + written, total - written)
                #endif
                if r > 0 {
                    written += r
                } else if r < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }
}
