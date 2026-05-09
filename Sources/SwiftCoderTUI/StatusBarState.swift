import Foundation

/// Status-bar state: project breadcrumb, optional active file, git branch,
/// LLM context utilisation, and sandbox flag.
///
/// `gitBranch` is populated asynchronously by the renderer to keep init
/// non-blocking on slow filesystems.
/// `contextPercent` and `sandboxEnabled` are optional: when `nil` the
/// corresponding badge is omitted from the status bar.
struct StatusBarState {
    var modeLabel: String = ""
    var projectPath: String = ""
    var activeFile: String? = nil
    var gitBranch: String? = nil
    /// Fraction of the model's context window in use, expressed as a
    /// percentage (e.g. `42.3` → "42.3% ctx").  `nil` hides the badge.
    var contextPercent: Double? = nil
    /// When non-nil, shows a `[Sandbox: Enabled]` or `[Sandbox: Disabled]`
    /// badge in the status bar.  `nil` hides the badge entirely.
    var sandboxEnabled: Bool? = nil

    /// Human-friendly path: `~`-substituted home and elided to `~/.../tail/leaf`
    /// when more than three components deep.
    func abbreviatedPath() -> String {
        let home = NSHomeDirectory()
        var display = projectPath.hasPrefix(home)
            ? "~" + projectPath.dropFirst(home.count)
            : projectPath
        let comps = display.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if comps.count > 3 {
            let prefix = display.hasPrefix("~") ? "~" : ""
            display = prefix + "/…/" + comps.suffix(2).joined(separator: "/")
        }
        return display
    }

    /// Read `.git/HEAD` from `directory`. Returns the branch name (for ref HEADs)
    /// or a short SHA (for detached HEADs). `nil` if the file is missing.
    static func readGitBranch(from directory: String) -> String? {
        let headPath = directory + "/.git/HEAD"
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        return trimmed.count >= 7 ? String(trimmed.prefix(7)) : trimmed
    }
}
