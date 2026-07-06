#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

// MARK: - Keystroke Types

public enum Keystroke {
    case character(Character)
    case enter
    case backspace
    case escape
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case shiftTab
    case shiftEnter
    case tab
    case ctrlP
    case shiftCtrlP
    case altEnter
    case ctrlC
    case delete
    case pageUp
    case pageDown
    case mouseScrollUp
    case mouseScrollDown

    // MARK: Readline-style editing shortcuts

    /// Ctrl+A — move cursor to the beginning of the line.
    case ctrlA
    /// Ctrl+E — move cursor to the end of the line.
    case ctrlE
    /// Ctrl+U — delete from the cursor to the start of the line.
    case ctrlU
    /// Ctrl+K — delete from the cursor to the end of the line.
    case ctrlK
    /// Ctrl+W — delete the previous whitespace-delimited word.
    case ctrlW
    /// Ctrl+L — signal the caller to clear and redraw the screen.
    case ctrlL
    /// Ctrl+V — trigger voice input (speech-to-text) if a provider is configured.
    case ctrlV
    /// Option+↑ — scroll the conversation history up.
    case optionUp
    /// Option+↓ — scroll the conversation history down.
    case optionDown

    // MARK: Bracketed paste

    /// A multi-line paste delivered as one event (requires bracketed-paste mode).
    ///
    /// When bracketed-paste is active the terminal wraps pasted text in
    /// `ESC[200~` … `ESC[201~` markers.  ``InputHandler`` accumulates the body
    /// and yields it here as a single event rather than hundreds of individual
    /// ``character(_:)`` keystrokes.
    case paste(String)

    case unknown
}

// MARK: - Async Keystroke Reader

public enum InputHandler {
    /// Returns an `AsyncStream` of parsed keystrokes read from stdin in raw mode.
    ///
    /// **Bracketed paste** is automatically enabled when the stream starts and
    /// disabled when it ends.  Pasted text is delivered as a single
    /// ``Keystroke/paste(_:)`` event rather than individual character events.
    ///
    /// **Readline shortcuts** are delivered as dedicated cases
    /// (``Keystroke/ctrlA``, ``Keystroke/ctrlE``, ``Keystroke/ctrlU``,
    /// ``Keystroke/ctrlK``, ``Keystroke/ctrlW``, ``Keystroke/ctrlL``) so that
    /// a ``LineEditor`` or custom handler can act on them without inspecting raw
    /// control-character codes.
    public static func keystrokes() -> AsyncStream<Keystroke> {
        AsyncStream { continuation in
            let task = Task.detached {
                // Enable bracketed paste mode so the terminal wraps pasted text in
                // ESC[200~ … ESC[201~ markers, letting us deliver it as one event.
                Self.writeEscape("\u{001B}[?2004h")

                var buf = [UInt8](repeating: 0, count: 64)

                // State machine for bracketed paste accumulation.
                var pasteMode = false
                var pasteBuffer = ""

                while !Task.isCancelled {
                    // Use poll() with a short timeout so cancellation is observable
                    // without requiring a keystroke to unblock read(). The previous
                    // unbounded read() would also spin at 100% CPU on EOF (n == 0)
                    // or transient errors.
                    var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                    let pr = poll(&pfd, 1, 100)
                    if pr == 0 { continue }
                    if pr < 0 {
                        if errno == EINTR { continue }
                        break
                    }
                    let n = read(STDIN_FILENO, &buf, buf.count)
                    if n == 0 { break }   // EOF — stdin closed
                    if n < 0 {
                        if errno == EINTR { continue }
                        break
                    }

                    // ── Bracketed paste: accumulate until ESC[201~ ───────────────
                    if pasteMode {
                        if let str = String(bytes: buf[0..<n], encoding: .utf8) {
                            let endMarker = "\u{001B}[201~"
                            if let markerRange = str.range(of: endMarker) {
                                pasteBuffer += str[str.startIndex..<markerRange.lowerBound]
                                continuation.yield(.paste(pasteBuffer))
                                pasteBuffer = ""
                                pasteMode = false
                                // Any bytes after the end marker are ignored here; in practice
                                // the marker always arrives as its own terminal write.
                            } else {
                                pasteBuffer += str
                            }
                        }
                        continue
                    }

                    // ── Check for paste-start marker ESC[200~ ────────────────────
                    // The marker is 6 bytes: 27 91 50 48 48 126 (ESC [ 2 0 0 ~).
                    // Use n >= 6 rather than n == 6: Terminal.app (and most modern
                    // terminal emulators) often send the start marker and the pasted
                    // content in a single write(), so the buffer will be larger than 6.
                    if n >= 6,
                       buf[0] == 27, buf[1] == 91, buf[2] == 50,
                       buf[3] == 48, buf[4] == 48, buf[5] == 126 {
                        pasteMode = true
                        pasteBuffer = ""
                        // If marker + content (+ possibly end marker) arrived together,
                        // process the trailing bytes as the first paste chunk right now.
                        if n > 6, let rest = String(bytes: buf[6..<n], encoding: .utf8) {
                            let endMarker = "\u{001B}[201~"
                            if let markerRange = rest.range(of: endMarker) {
                                pasteBuffer = String(rest[rest.startIndex..<markerRange.lowerBound])
                                continuation.yield(.paste(pasteBuffer))
                                pasteBuffer = ""
                                pasteMode = false
                            } else {
                                pasteBuffer = rest
                            }
                        }
                        continue
                    }

                    // ── Normal key parsing ───────────────────────────────────────
                    if n == 1 {
                        let byte = buf[0]
                        switch byte {
                        case 13:        // Enter / CR (Send)
                            continuation.yield(.enter)
                        case 10:        // LF (New line / Shift+Enter in some terminals)
                            continuation.yield(.shiftEnter)
                        case 9:         // Tab
                            continuation.yield(.tab)
                        case 27:        // Escape — standalone or first byte of a split sequence
                            // Use poll() with a 50 ms timeout (the ncurses/Vim approach).
                            // O_NONBLOCK fires before the rest of the sequence arrives in
                            // the kernel buffer; poll() waits just long enough for it.
                            // poll() is portable across Darwin and Linux without
                            // platform-specific fd_set tuple-bit manipulation.
                            var escPfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                            let ready = poll(&escPfd, 1, 50)

                            var extra = [UInt8](repeating: 0, count: 31)
                            let m: Int = ready > 0 ? read(STDIN_FILENO, &extra, extra.count) : 0

                            if m > 0 {
                                if extra[0] == 91 { // ESC [ ...
                                    let s = "\u{001B}" + (String(bytes: extra[0..<m], encoding: .utf8) ?? "")
                                    if s == "\u{001B}[13;2u" || s == "\u{001B}[10;2u" {
                                        continuation.yield(.shiftEnter)
                                    } else if s == "\u{001B}[13;3u" {
                                        continuation.yield(.altEnter)
                                    } else if s == "\u{001B}[112;6u" || s == "\u{001B}[80;6u" {
                                        continuation.yield(.shiftCtrlP)
                                    } else if s == "\u{001B}[112;5u" || s == "\u{001B}[80;5u" {
                                        continuation.yield(.ctrlP)
                                    } else if s == "\u{001B}[1;3A" {
                                        continuation.yield(.optionUp)
                                    } else if s == "\u{001B}[1;3B" {
                                        continuation.yield(.optionDown)
                                    } else if m >= 2 {
                                        switch extra[1] {
                                        case 65: continuation.yield(.arrowUp)
                                        case 66: continuation.yield(.arrowDown)
                                        case 67: continuation.yield(.arrowRight)
                                        case 68: continuation.yield(.arrowLeft)
                                        case 90: continuation.yield(.shiftTab)
                                        case 53: if m >= 3, extra[2] == 126 { continuation.yield(.pageUp) }
                                        case 54: if m >= 3, extra[2] == 126 { continuation.yield(.pageDown) }
                                        case 51: if m >= 3, extra[2] == 126 { continuation.yield(.delete) }
                                        default: break
                                        }
                                    }
                                } else if extra[0] == 79, m >= 2 { // ESC O ... (SS3 — application cursor key mode)
                                    switch extra[1] {
                                    case 65: continuation.yield(.arrowUp)
                                    case 66: continuation.yield(.arrowDown)
                                    case 67: continuation.yield(.arrowRight)
                                    case 68: continuation.yield(.arrowLeft)
                                    default: break
                                    }
                                } else if extra[0] == 13 || extra[0] == 10 { // ESC + CR/LF = Alt+Enter
                                    continuation.yield(.altEnter)
                                }
                                // Unknown ESC sequence — ignore
                            } else {
                                continuation.yield(.escape)
                            }
                        case 127, 8:    // Backspace / DEL
                            continuation.yield(.backspace)
                        case 1:         // Ctrl+A — beginning of line
                            continuation.yield(.ctrlA)
                        case 3:         // Ctrl+C
                            continuation.yield(.ctrlC)
                        case 5:         // Ctrl+E — end of line
                            continuation.yield(.ctrlE)
                        case 11:        // Ctrl+K — kill to end
                            continuation.yield(.ctrlK)
                        case 12:        // Ctrl+L — clear screen
                            continuation.yield(.ctrlL)
                        case 16:        // Ctrl+P
                            continuation.yield(.ctrlP)
                        case 21:        // Ctrl+U — kill to start
                            continuation.yield(.ctrlU)
                        case 22:        // Ctrl+V — voice input
                            continuation.yield(.ctrlV)
                        case 23:        // Ctrl+W — kill previous word
                            continuation.yield(.ctrlW)
                        case 1...26:    // Other control chars — ignore
                            break
                        default:
                            let scalar = Unicode.Scalar(byte)
                            continuation.yield(.character(Character(scalar)))
                        }
                    } else if n >= 3, buf[0] == 27, buf[1] == 91 { // ESC [
                        // Handle Shift+Enter (CSI 13;2u or CSI 10;2u)
                        let s = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
                        if s == "\u{001B}[13;2u" || s == "\u{001B}[10;2u" {
                            continuation.yield(.shiftEnter)
                        } else if s == "\u{001B}[13;3u" {
                            continuation.yield(.altEnter)
                        } else if s == "\u{001B}[112;6u" || s == "\u{001B}[80;6u" {
                            continuation.yield(.shiftCtrlP)
                        } else if s == "\u{001B}[112;5u" || s == "\u{001B}[80;5u" {
                            continuation.yield(.ctrlP)
                        } else if s == "\u{001B}[1;3A" {
                            continuation.yield(.optionUp)
                        } else if s == "\u{001B}[1;3B" {
                            continuation.yield(.optionDown)
                        } else if buf[2] == 60 {
                            // Handle Mouse SGR: ESC [ < P ; X ; Y M/m
                            if s.hasPrefix("\u{001B}[<") {
                                // 64/65 are standard scroll, 0/1 are often sent by trackpads in some modes
                                if s.contains(";64;") || s.contains(";0;") { 
                                    continuation.yield(.mouseScrollUp)
                                } else if s.contains(";65;") || s.contains(";1;") {
                                    continuation.yield(.mouseScrollDown)
                                }
                            }
                        } else {
                            switch buf[2] {
                            case 65: continuation.yield(.arrowUp)
                            case 66: continuation.yield(.arrowDown)
                            case 67: continuation.yield(.arrowRight)
                            case 68: continuation.yield(.arrowLeft)
                            case 90: continuation.yield(.shiftTab)  // ESC [ Z
                            case 53: // PageUp: ESC [ 5 ~
                                if n >= 4, buf[3] == 126 { continuation.yield(.pageUp) }
                            case 54: // PageDown: ESC [ 6 ~
                                if n >= 4, buf[3] == 126 { continuation.yield(.pageDown) }
                            case 51:
                                if n >= 4, buf[3] == 126 {
                                    continuation.yield(.delete)
                                }
                            default:
                                continuation.yield(.unknown)
                            }
                        }
                    } else if n >= 3, buf[0] == 27, buf[1] == 79 { // ESC O (SS3 — application cursor key mode)
                        switch buf[2] {
                        case 65: continuation.yield(.arrowUp)
                        case 66: continuation.yield(.arrowDown)
                        case 67: continuation.yield(.arrowRight)
                        case 68: continuation.yield(.arrowLeft)
                        default: break
                        }
                    } else if n >= 2, buf[0] == 27 { // Option/Alt + Key
                        if buf[1] == 13 || buf[1] == 10 { // Option+Enter
                            continuation.yield(.altEnter)
                        }
                    } else {
                        // Multi-byte UTF-8 character
                        let data = Data(buf[0..<n])
                        if let str = String(data: data, encoding: .utf8) {
                            for ch in str {
                                continuation.yield(.character(ch))
                            }
                        }
                    }
                }

                // Disable bracketed paste mode before exiting.
                Self.writeEscape("\u{001B}[?2004l")
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private helpers

    /// Write an escape sequence directly to stdout (used to toggle terminal modes).
    private static func writeEscape(_ s: String) {
        try? FileHandle.standardOutput.write(contentsOf: Data(s.utf8))
    }
}
