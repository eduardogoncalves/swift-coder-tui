/// Utilities for measuring and manipulating the visible terminal width of strings.
///
/// Examples:
/// ```
/// VisibleWidth.measure("hello") == 5
/// VisibleWidth.measure("\u{1B}[31mhello\u{1B}[0m") == 5
/// VisibleWidth.measure("👋") == 2
/// VisibleWidth.measure("héllo") == 5  // combining mark on e doesn't add width
/// VisibleWidth.measure("中文") == 4
/// ```
public enum VisibleWidth {

    /// Returns the number of terminal columns this string would occupy when printed.
    /// Strips all ANSI/OSC escape sequences and accounts for wide characters.
    public static func measure(_ s: String) -> Int {
        var width = 0
        for char in stripAnsi(s) {
            width += graphemeWidth(char)
        }
        return width
    }

    /// Returns a copy of `s` with all ANSI/OSC escape sequences removed.
    public static func stripAnsi(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.utf8.count)
        var scalars = s.unicodeScalars.makeIterator()

        while let sc = scalars.next() {
            guard sc.value == 0x1B else {
                result.unicodeScalars.append(sc)
                continue
            }
            guard let next = scalars.next() else { break }

            if next.value == 0x5B {  // ESC [ — CSI sequence
                // Consume until terminator in 0x40...0x7E
                while let c = scalars.next() {
                    if (0x40...0x7E).contains(c.value) { break }
                }
            } else if next.value == 0x5D {  // ESC ] — OSC sequence
                // Consume until BEL (0x07) or ESC \ (0x1B 0x5C)
                while let c = scalars.next() {
                    if c.value == 0x07 { break }
                    if c.value == 0x1B {
                        _ = scalars.next()  // consume the \ (0x5C)
                        break
                    }
                }
            }
            // Other ESC sequences: skip the second byte and move on
        }
        return result
    }

    /// Truncates `s` to at most `maxWidth` visible columns, preserving ANSI styling sequences.
    /// If truncation occurs and the ellipsis fits within `maxWidth`, it is appended followed
    /// by a `ESC[0m` reset to avoid style bleed.
    public static func truncate(_ s: String, maxWidth: Int, ellipsis: String = "…") -> String {
        let ellipsisWidth = measure(ellipsis)
        var result = ""
        result.reserveCapacity(s.utf8.count)
        var visibleWidth = 0
        var truncated = false

        // Walk the scalar view, emitting escape sequences verbatim and measuring
        // visible grapheme clusters by operating on the Character layer.
        let sv = s.unicodeScalars
        var si = sv.startIndex

        while si < sv.endIndex {
            let sc = sv[si]

            if sc.value == 0x1B {
                let afterEsc = sv.index(after: si)
                guard afterEsc < sv.endIndex else { break }
                let next = sv[afterEsc]

                if next.value == 0x5B {  // CSI: ESC [
                    var end = sv.index(after: afterEsc)
                    while end < sv.endIndex {
                        let c = sv[end]
                        end = sv.index(after: end)
                        if (0x40...0x7E).contains(c.value) { break }
                    }
                    result += String(sv[si..<end])
                    si = end
                } else if next.value == 0x5D {  // OSC: ESC ]
                    var end = sv.index(after: afterEsc)
                    while end < sv.endIndex {
                        let c = sv[end]
                        end = sv.index(after: end)
                        if c.value == 0x07 { break }
                        if c.value == 0x1B {
                            if end < sv.endIndex { end = sv.index(after: end) }
                            break
                        }
                    }
                    result += String(sv[si..<end])
                    si = end
                } else {
                    si = sv.index(after: afterEsc)
                }
                continue
            }

            // Map the scalar index back to a Character index so we get the full
            // grapheme cluster (e.g. base + combining marks, ZWJ emoji sequences).
            // If the scalar position doesn't sit on a Character boundary
            // (mid-grapheme — possible after raw scalar truncation), fall back
            // by walking forward to the next boundary using the String view.
            let charIdx: String.Index
            if let mapped = si.samePosition(in: s) {
                charIdx = mapped
            } else {
                // Walk to the start of the enclosing grapheme cluster by asking
                // the Character view for the index containing this scalar.
                charIdx = s.indices.first(where: { idx in
                    let next = s.index(after: idx)
                    return idx.samePosition(in: sv).map { $0 <= si } ?? false
                        && next.samePosition(in: sv).map { si < $0 } ?? false
                }) ?? s.endIndex
                if charIdx == s.endIndex { break }
            }
            let char = s[charIdx]
            let w = graphemeWidth(char)

            if visibleWidth + w > maxWidth {
                truncated = true
                break
            }
            visibleWidth += w
            result.append(char)
            // Advance past all scalars belonging to this grapheme cluster.
            let nextCharIdx = s.index(after: charIdx)
            si = nextCharIdx.samePosition(in: sv) ?? sv.endIndex
        }

        if truncated && visibleWidth + ellipsisWidth <= maxWidth {
            result += ellipsis + "\u{1B}[0m"
        }
        return result
    }
}

// MARK: - Private helpers

private func charWidth(_ scalar: Unicode.Scalar) -> Int {
    let v = scalar.value
    if v == 0 { return 0 }
    if v < 0x20 || (v >= 0x7F && v < 0xA0) { return 0 }
    if scalar.properties.generalCategory == .nonspacingMark { return 0 }
    if scalar.properties.generalCategory == .enclosingMark { return 0 }
    if scalar.properties.generalCategory == .format { return 0 }
    if (0x1100...0x115F).contains(v) ||   // Hangul Jamo
       (0x2E80...0x303E).contains(v) ||   // CJK Radicals, Kangxi
       (0x3041...0x33FF).contains(v) ||   // Hiragana, Katakana, etc.
       (0x3400...0x4DBF).contains(v) ||   // CJK Extension A
       (0x4E00...0x9FFF).contains(v) ||   // CJK Unified
       (0xA000...0xA4CF).contains(v) ||   // Yi
       (0xAC00...0xD7A3).contains(v) ||   // Hangul Syllables
       (0xF900...0xFAFF).contains(v) ||   // CJK Compat Ideographs
       (0xFE30...0xFE4F).contains(v) ||   // CJK Compat Forms
       (0xFF00...0xFF60).contains(v) ||   // Fullwidth Forms
       (0xFFE0...0xFFE6).contains(v) ||   // Fullwidth Signs
       (0x2600...0x26FF).contains(v) ||   // Misc Symbols (☀️☁️⚠️ etc.) — rendered
                                           // as emoji-width-2 by every terminal
                                           // this app targets; missing this range
                                           // undercounted every "⚠️ warning" line
                                           // by 1 column.
       (0x2700...0x27BF).contains(v) ||   // Dingbats (✅❌✂️✈️ etc.) — same
                                           // emoji-width-2 rendering; missing this
                                           // undercounted every tool-result line
                                           // (✅/❌ prefix) by 1 column, which
                                           // compounds across a run's tool calls:
                                           // the renderer's row-count bookkeeping
                                           // (renderedFooterLineCount /
                                           // renderedCursorFooterRow) drifts by 1
                                           // row further behind the real terminal
                                           // cursor position on every such line,
                                           // so the footer/spinner block is placed
                                           // progressively further off from where
                                           // it should be the longer a run with
                                           // many tool calls (e.g. a sub-agent
                                           // iterating several tool calls in a
                                           // row) goes on.
       (0x1F300...0x1F64F).contains(v) || // Misc Symbols / Emoji
       (0x1F680...0x1F6FF).contains(v) || // Transport / Map
       (0x1F900...0x1F9FF).contains(v) || // Supplemental Symbols / Pictographs
       (0x20000...0x2FFFD).contains(v) || // CJK Extension B–F
       (0x30000...0x3FFFD).contains(v) {  // CJK Extension G
        return 2
    }
    return 1
}

private func graphemeWidth(_ char: Character) -> Int {
    var maxW = 0
    for scalar in char.unicodeScalars {
        let v = scalar.value
        if v == 0x200D || (0xFE00...0xFE0F).contains(v) { continue }  // ZWJ, variation selectors
        maxW = max(maxW, charWidth(scalar))
    }
    return maxW
}
