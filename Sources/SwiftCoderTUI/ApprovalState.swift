import Foundation

/// Tool-call approval prompt: message, options, and the currently highlighted
/// option. Replaces the unnamed tuple that used to live on `Renderer`.
struct ApprovalState {
    var message: String
    var options: [String]
    var selected: Int
    var isPlanMode: Bool

    static func make(tool: String, args: String) -> ApprovalState {
        let command = displayCommand(tool: tool, args: args)
        let message = "Do you want to proceed with '\(command)'?"
        let options = [
            "Yes, allow once",
            "Yes, allow '\(command)' always in this session",
            "Yes, allow all tool calls (autopilot mode)",
            "No, suggest changes (esc)",
        ]
        return ApprovalState(message: message, options: options, selected: 0, isPlanMode: false)
    }

    static func makePlanMode(tool: String, args: String) -> ApprovalState {
        let message = "Tool '\(tool)' is blocked in PLAN mode. Switch to AGENT mode?"
        let options = [
            "Switch to AGENT mode and allow",
            "Deny",
        ]
        return ApprovalState(message: message, options: options, selected: 0, isPlanMode: true)
    }

    mutating func move(offset: Int) {
        selected = (selected + offset + options.count) % options.count
    }

    private static func displayCommand(tool: String, args: String) -> String {
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArgs.isEmpty else { return tool }
        if trimmedArgs == tool { return tool }
        if trimmedArgs.hasPrefix("\(tool) ") { return trimmedArgs }
        return "\(tool) \(trimmedArgs)"
    }
}

/// Generic option-picker prompt: a question with a list of choices and a
/// highlighted selection. Used by the TUI to replace raw-terminal
/// `InteractiveInput.selectOption` calls so the renderer owns the UI.
struct OptionSelectState {
    var prompt: String
    var options: [String]
    var selected: Int
    /// When `true`, pressing Escape selects the **last** option instead of
    /// cancelling (mirrors `InteractiveInput.selectOption(escSelectsLastOption:)`).
    var escSelectsLastOption: Bool

    mutating func move(offset: Int) {
        selected = (selected + offset + options.count) % options.count
    }
}
