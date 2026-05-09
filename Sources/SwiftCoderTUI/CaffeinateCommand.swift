import Foundation

// MARK: - CaffeinateCommandIntent

public enum CaffeinateCommandIntent: Equatable, Sendable {
    case openMenu
    case on
    case off
    case busy
    case duration(seconds: Int)
    case invalid(String)
}

// MARK: - CaffeinateCommandParser

public enum CaffeinateCommandParser {

    public static func resolve(input: String) -> CaffeinateCommandIntent? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })

        guard let command = parts.first?.lowercased(), command == "/caffeinate" else {
            return nil
        }

        guard parts.count > 1 else { return .openMenu }

        let arg = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !arg.isEmpty else { return .openMenu }

        switch arg.lowercased() {
        case "on":   return .on
        case "off":  return .off
        case "busy": return .busy
        default:
            if let seconds = parseDuration(arg) { return .duration(seconds: seconds) }
            return .invalid(arg)
        }
    }

    /// Parses duration strings: plain integers (seconds), or suffixed `Ns`, `Nm`, `Nh`.
    public static func parseDuration(_ arg: String) -> Int? {
        let lower = arg.lowercased()
        if lower.hasSuffix("h"), let n = Int(lower.dropLast()), n > 0 { return n * 3_600 }
        if lower.hasSuffix("m"), let n = Int(lower.dropLast()), n > 0 { return n * 60 }
        if lower.hasSuffix("s"), let n = Int(lower.dropLast()), n > 0 { return n }
        if let n = Int(lower), n > 0 { return n }
        return nil
    }

    /// Menu items shown when `/caffeinate` is entered without an argument.
    public static func menuItems() -> [(name: String, desc: String)] {
        [
            (name: "/caffeinate on",   desc: "Prevent idle and system sleep"),
            (name: "/caffeinate busy", desc: "Prevent sleep and display dimming"),
            (name: "/caffeinate off",  desc: "Stop keep-alive, allow sleep"),
            (name: "/caffeinate 30m",  desc: "Keep awake for 30 minutes"),
            (name: "/caffeinate 1h",   desc: "Keep awake for 1 hour"),
            (name: "/caffeinate 2h",   desc: "Keep awake for 2 hours"),
        ]
    }
}

// MARK: - CaffeinateSlashCommand

/// Slash-command that provides autocomplete for `/caffeinate [on|off|busy|<duration>]`.
public struct CaffeinateSlashCommand: SlashCommand {
    public let name: String = "caffeinate"
    public let description: String? = "Manage keep-alive mode (prevents system sleep)"

    public init() {}

    public func argumentCompletions(prefix: String) -> [AutocompleteItem] {
        let typed = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let options: [(value: String, desc: String)] = [
            ("on",   "Prevent idle and system sleep"),
            ("off",  "Stop keep-alive, allow sleep"),
            ("busy", "Prevent sleep and display dimming"),
            ("30m",  "Keep awake for 30 minutes"),
            ("1h",   "Keep awake for 1 hour"),
            ("2h",   "Keep awake for 2 hours"),
        ]
        return options
            .filter { typed.isEmpty || $0.value.hasPrefix(typed) }
            .map { AutocompleteItem(value: $0.value, label: "/caffeinate \($0.value)", description: $0.desc) }
    }
}
