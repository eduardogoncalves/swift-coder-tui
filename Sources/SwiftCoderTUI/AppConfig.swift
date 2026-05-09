import Foundation

// MARK: - App Configuration
//
// Coding agents implementing a TUI tool should instantiate AppConfig with their
// own app name, version, models, modes, and slash-commands. The Renderer and
// related components read exclusively from this config so that nothing about
// the identity of the tool is baked into the library itself.

public struct AppConfig: Sendable {

    // MARK: - Nested Types

    /// A selectable AI model shown in the status bar (Ctrl+P to cycle).
    public struct ModelConfig: Sendable {
        public let id: String       // stable identifier used in API calls
        public let label: String    // display label shown in the status bar badge

        public init(id: String, label: String) {
            self.id    = id
            self.label = label
        }
    }

    /// A permission / context mode shown in the status bar (Shift+Tab to cycle).
    public struct ModeConfig: Sendable {
        public let id: String           // stable identifier
        public let label: String        // display label (e.g. "LOW", "HIGH")
        public let barColor: String     // ANSI escape for the input-box separators
        public let badgeColor: String   // ANSI escape for thinking annotations

        public init(id: String, label: String, barColor: String, badgeColor: String) {
            self.id         = id
            self.label      = label
            self.barColor   = barColor
            self.badgeColor = badgeColor
        }
    }

    /// A slash-command shown in the autocomplete popup when the user types `/`.
    public struct CommandConfig: Sendable {
        public let name: String         // e.g. "/clear"
        public let description: String  // one-line description shown next to the name

        public init(name: String, description: String) {
            self.name        = name
            self.description = description
        }
    }

    /// A keyboard shortcut shown in the `?` help overlay.
    public struct ShortcutConfig: Sendable {
        public let key: String          // human-readable key combination, e.g. "Ctrl+P"
        public let description: String  // what it does

        public init(key: String, description: String) {
            self.key         = key
            self.description = description
        }
    }

    // MARK: - Top-level fields

    /// Name shown in the welcome banner and window title.
    public let appName: String

    /// Semantic version string, e.g. "1.0.0".
    public let version: String

    /// Short tagline appended after the app name in the welcome banner.
    public let welcomeMessage: String

    /// Ordered list of models the user can cycle through with Ctrl+P.
    public let models: [ModelConfig]

    /// Ordered list of modes the user can cycle through with Shift+Tab.
    public let modes: [ModeConfig]

    /// Slash-commands surfaced in the `/` autocomplete popup.
    public let commands: [CommandConfig]

    /// Shortcuts shown in the `?` help overlay.
    public let keyboardShortcuts: [ShortcutConfig]

    /// Optional voice-to-text provider.  When set, `Ctrl+V` triggers a
    /// transcription and prefills the input buffer with the result so the
    /// user can review before sending.  When `nil`, `Ctrl+V` is ignored.
    public var voiceInputProvider: (any VoiceInputProvider)?

    /// When true, render top-bar debug markers (tb# sequence + trigger).
    /// Disabled by default.
    public let topBarDebugEnabled: Bool

    /// Index into `models` to use on startup.
    public let defaultModelIndex: Int

    /// Index into `modes` to use on startup.
    public let defaultModeIndex: Int

    // MARK: - Init

    public init(
        appName: String,
        version: String,
        welcomeMessage: String,
        models: [ModelConfig],
        modes: [ModeConfig],
        commands: [CommandConfig],
        keyboardShortcuts: [ShortcutConfig] = AppConfig.defaultShortcuts,
        defaultModelIndex: Int = 0,
        defaultModeIndex: Int = 0,
        voiceInputProvider: (any VoiceInputProvider)? = nil,
        topBarDebugEnabled: Bool = false
    ) {
        self.appName             = appName
        self.version             = version
        self.welcomeMessage      = welcomeMessage
        self.models              = models
        self.modes               = modes
        self.commands            = commands
        self.keyboardShortcuts   = keyboardShortcuts
        self.defaultModelIndex   = max(0, min(defaultModelIndex, models.count - 1))
        self.defaultModeIndex    = max(0, min(defaultModeIndex,  modes.count  - 1))
        self.voiceInputProvider  = voiceInputProvider
        self.topBarDebugEnabled  = topBarDebugEnabled
    }

    // MARK: - Defaults

    /// Standard keyboard shortcuts for any Swift Coder TUI app.
    public static let defaultShortcuts: [ShortcutConfig] = [
        ShortcutConfig(key: "Enter",                              description: "Send message"),
        ShortcutConfig(key: "Shift+Enter / Opt+Enter / Ctrl+J",  description: "New line"),
        ShortcutConfig(key: "\\ + Enter",                         description: "New line (any terminal)"),
        ShortcutConfig(key: "↑ / ↓",                             description: "Navigate input history"),
        ShortcutConfig(key: "Shift+Tab",                          description: "Cycle mode"),
        ShortcutConfig(key: "Ctrl+P / ⇧Ctrl+P",                  description: "Cycle model forward / back"),
        ShortcutConfig(key: "Ctrl+V",                             description: "Voice input (speech-to-text)"),
        ShortcutConfig(key: "Esc",                                description: "Cancel generation"),
        ShortcutConfig(key: "Ctrl+C",                             description: "Quit"),
    ]
}
