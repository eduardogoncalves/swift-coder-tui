/// OSC 8 hyperlink support for terminal emulators.
///
/// Terminals that support OSC 8 (iTerm2, Kitty, WezTerm, modern GNOME Terminal, etc.)
/// render the wrapped text as a clickable hyperlink.
///
/// The escape sequence format is:
/// ```
/// ESC ] 8 ; <params> ; <url> ESC \\ <text> ESC ] 8 ; ; ESC \\
/// ```
public enum Hyperlink {

    // MARK: - Public API

    /// Wraps `text` in an OSC 8 hyperlink sequence pointing to `url`.
    ///
    /// - Parameters:
    ///   - url: The destination URL (e.g. `"https://example.com"`).
    ///   - text: The visible label rendered in the terminal.
    ///   - id: An optional unique link identifier used to highlight all instances of
    ///     the same logical link simultaneously (passed as `id=<id>` in the params field).
    /// - Returns: A `String` containing the OSC 8 escape sequence.
    ///
    /// Example:
    /// ```swift
    /// let link = Hyperlink.link(url: "https://swift.org", text: "Swift.org")
    /// print(link) // prints clickable "Swift.org" in supporting terminals
    /// ```
    public static func link(url: String, text: String, id: String? = nil) -> String {
        let params = id.map { "id=\($0)" } ?? ""
        let open  = "\u{1B}]8;\(params);\(url)\u{1B}\\"
        let close = "\u{1B}]8;;\u{1B}\\"
        return "\(open)\(text)\(close)"
    }

}
