import Foundation

// MARK: - Session Model

public struct SessionEntry: Sendable {
    public enum Role: Sendable {
        case user
        /// `badgeColor` is an ANSI escape from the active `AppConfig.ModeConfig.badgeColor`.
        case thinking(badgeColor: String)
        case assistant
        case stats
        case toolCall
        case toolOutput
    }

    public let role: Role
    public let content: String
    public let tokenCount: Int?
    public let tokensPerSecond: Double?
    public let elapsed: TimeInterval?

    public init(role: Role, content: String, tokenCount: Int? = nil,
                tokensPerSecond: Double? = nil, elapsed: TimeInterval? = nil) {
        self.role             = role
        self.content          = content
        self.tokenCount       = tokenCount
        self.tokensPerSecond  = tokensPerSecond
        self.elapsed          = elapsed
    }

    /// Render this entry as a styled string.
    public func render() -> String {
        switch role {
        case .user:
            // Re-apply bg+fg on every line so multiline messages have a
            // consistent full-width background across all continuation lines.
            let lines = content.components(separatedBy: "\n")
            let prefix = "\(DesignSystem.User.bg)\(DesignSystem.User.fg)"
            let rendered = lines.enumerated().map { i, line in
                let label = i == 0 ? " > " : "   "
                return "\(prefix)\(label)\(line) \(DesignSystem.reset)"
            }.joined(separator: "\n")
            return rendered
        case .thinking(let badgeColor):
            return "\(badgeColor)\(DesignSystem.dim)· \(content)\(DesignSystem.reset)"
        case .assistant:
            return "\(DesignSystem.reset)\(content)\(DesignSystem.reset)"
        case .stats:
            if let tc = tokenCount, let tps = tokensPerSecond, let el = elapsed {
                return "\(DesignSystem.darkGray)Generated \(tc) tokens (\(String(format: "%.1f", tps)) tok/s, \(String(format: "%.1f", el))s)\(DesignSystem.reset)"
            }
            return "\(DesignSystem.darkGray)\(content)\(DesignSystem.reset)"
        case .toolCall:
            let parts = content.split(separator: " ", maxSplits: 1).map(String.init)
            let tool = parts.first ?? content
            let args = parts.count > 1 ? parts[1] : ""
            let gray = DesignSystem.darkGray
            let rst  = DesignSystem.reset
            let header = "\(gray)  ╭── \(rst)\(DesignSystem.Tool.call)🔨 \(tool)\(rst)"
            let argsLine = args.isEmpty ? "" : "\n\(gray)  │  \(rst)\(DesignSystem.dim)\(args)\(rst)"
            let footer = "\n\(gray)  ╰─────────────────────────\(rst)"
            return "\(header)\(argsLine)\(footer)"
        case .toolOutput:
            let lines = content.components(separatedBy: "\n")
            let gray = DesignSystem.darkGray
            let rst  = DesignSystem.reset
            let header = "\(gray)  ╭── output ─────────────────\(rst)"
            let body   = lines.map { "\(gray)  │ \(rst)\(DesignSystem.Tool.output)\($0)\(rst)" }.joined(separator: "\n")
            let footer = "\(gray)  ╰────────────────────────────\(rst)"
            return "\(header)\n\(body)\n\(footer)"
        }
    }
}
