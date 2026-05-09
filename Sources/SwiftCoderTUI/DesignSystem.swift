import Foundation
import os

// MARK: - Palette

/// A semantic color palette used by the design system.
public struct Palette: Sendable {
    public var primary:    Color
    public var secondary:  Color
    public var accent:     Color
    public var success:    Color
    public var warning:    Color
    public var danger:     Color
    public var info:       Color
    public var muted:      Color
    public var background: Color
    public var foreground: Color
    public var surface:    Color
    public var border:     Color

    public init(
        primary: Color, secondary: Color, accent: Color,
        success: Color, warning: Color, danger: Color,
        info: Color, muted: Color, background: Color,
        foreground: Color, surface: Color, border: Color
    ) {
        self.primary    = primary
        self.secondary  = secondary
        self.accent     = accent
        self.success    = success
        self.warning    = warning
        self.danger     = danger
        self.info       = info
        self.muted      = muted
        self.background = background
        self.foreground = foreground
        self.surface    = surface
        self.border     = border
    }
}

// MARK: - Theme

public enum Theme: String, CaseIterable, Sendable {
    case classic, monokai, solarizedDark, solarizedLight, dracula, nord

    public var palette: Palette {
        switch self {
        case .classic:
            return Palette(
                primary:    .ansi(.cyan),
                secondary:  .ansi(.magenta),
                accent:     .ansi(.brightYellow),
                success:    .ansi(.green),
                warning:    .ansi(.yellow),
                danger:     .ansi(.red),
                info:       .ansi(.brightCyan),
                muted:      .ansi(.brightBlack),
                background: .ansi(.black),
                foreground: .xterm(255),
                surface:    .xterm(238),
                border:     .ansi(.brightBlack)
            )
        case .monokai:
            return Palette(
                primary:    .hex(0x66D9E8),
                secondary:  .hex(0xAE81FF),
                accent:     .hex(0xF92672),
                success:    .hex(0xA6E22E),
                warning:    .hex(0xE6DB74),
                danger:     .hex(0xF92672),
                info:       .hex(0x66D9E8),
                muted:      .hex(0x75715E),
                background: .hex(0x272822),
                foreground: .hex(0xF8F8F2),
                surface:    .hex(0x3E3D32),
                border:     .hex(0x75715E)
            )
        case .solarizedDark:
            return Palette(
                primary:    .hex(0x268BD2),
                secondary:  .hex(0xD33682),
                accent:     .hex(0xB58900),
                success:    .hex(0x859900),
                warning:    .hex(0xCB4B16),
                danger:     .hex(0xDC322F),
                info:       .hex(0x2AA198),
                muted:      .hex(0x586E75),
                background: .hex(0x002B36),
                foreground: .hex(0x839496),
                surface:    .hex(0x073642),
                border:     .hex(0x073642)
            )
        case .solarizedLight:
            return Palette(
                primary:    .hex(0x268BD2),
                secondary:  .hex(0xD33682),
                accent:     .hex(0xB58900),
                success:    .hex(0x859900),
                warning:    .hex(0xCB4B16),
                danger:     .hex(0xDC322F),
                info:       .hex(0x2AA198),
                muted:      .hex(0x93A1A1),
                background: .hex(0xFDF6E3),
                foreground: .hex(0x657B83),
                surface:    .hex(0xEEE8D5),
                border:     .hex(0xEEE8D5)
            )
        case .dracula:
            return Palette(
                primary:    .hex(0xBD93F9),
                secondary:  .hex(0xFF79C6),
                accent:     .hex(0xFF79C6),
                success:    .hex(0x50FA7B),
                warning:    .hex(0xF1FA8C),
                danger:     .hex(0xFF5555),
                info:       .hex(0x8BE9FD),
                muted:      .hex(0x6272A4),
                background: .hex(0x282A36),
                foreground: .hex(0xF8F8F2),
                surface:    .hex(0x44475A),
                border:     .hex(0x44475A)
            )
        case .nord:
            return Palette(
                primary:    .hex(0x81A1C1),
                secondary:  .hex(0xB48EAD),
                accent:     .hex(0x88C0D0),
                success:    .hex(0xA3BE8C),
                warning:    .hex(0xEBCB8B),
                danger:     .hex(0xBF616A),
                info:       .hex(0x8FBCBB),
                muted:      .hex(0x616E88),
                background: .hex(0x2E3440),
                foreground: .hex(0xD8DEE9),
                surface:    .hex(0x3B4252),
                border:     .hex(0x434C5E)
            )
        }
    }
}

// MARK: - DesignSystem

public enum DesignSystem {

    // MARK: - Theme
    //
    // The active theme is global, mutable, and read from many concurrency
    // contexts (multiple actors, background tasks). To keep the synchronous
    // `palette` accessor — which is called from a long, hot rendering path —
    // and still be safe under Swift Strict Concurrency, the storage is hidden
    // behind an unfair lock.
    //
    // Trade-off: this is faster than an actor (no async hop on every read) and
    // safer than a bare `nonisolated(unsafe)` `var`.

    private static let themeLock = OSAllocatedUnfairLock(initialState: Theme.classic)

    public static var currentTheme: Theme {
        get {
            themeLock.withLock { $0 }
        }
        set {
            themeLock.withLock { $0 = newValue }
        }
    }

    public static var palette: Palette { currentTheme.palette }

    public static func setTheme(_ theme: Theme) {
        currentTheme = theme
    }

    // MARK: - Text Attributes (raw ANSI, not theme-dependent)

    public static let reset = "\u{001B}[0m"
    public static let bold  = "\u{001B}[1m"
    public static let dim   = "\u{001B}[2m"

    // MARK: - Basic Colors (theme-aware via palette)

    public static var white:         String { palette.foreground.foregroundSGR }
    public static var darkGray:      String { palette.muted.foregroundSGR }
    public static var green:         String { palette.success.foregroundSGR }
    public static var cyan:          String { palette.primary.foregroundSGR }
    public static var brightCyan:    String { palette.info.foregroundSGR }
    public static var yellow:        String { palette.warning.foregroundSGR }
    public static var brightYellow:  String { palette.accent.foregroundSGR }
    public static var magenta:       String { palette.secondary.foregroundSGR }
    public static var red:           String { palette.danger.foregroundSGR }

    // Raw ANSI shims — no palette semantic equivalent
    public static let brightWhite:   String = Color.ansi(.brightWhite).foregroundSGR
    public static let brightMagenta: String = Color.ansi(.brightMagenta).foregroundSGR
    public static let brightRed:     String = Color.ansi(.brightRed).foregroundSGR

    // MARK: - Component Styles

    public enum User {
        public static var bg: String { DesignSystem.palette.surface.backgroundSGR }
        public static var fg: String { DesignSystem.palette.foreground.foregroundSGR }
    }

    public enum Status {
        public static var info:    String { DesignSystem.palette.info.foregroundSGR }
        public static var success: String { DesignSystem.palette.success.foregroundSGR }
        public static var warning: String { DesignSystem.palette.warning.foregroundSGR }
        public static var error:   String { DesignSystem.palette.danger.foregroundSGR }
        public static var pending: String { DesignSystem.palette.muted.foregroundSGR }
    }

    public enum Tool {
        public static var call:   String { DesignSystem.palette.accent.foregroundSGR }
        public static var output: String { DesignSystem.palette.muted.foregroundSGR }
    }

    public enum Autocomplete {
        public static var marker:       String { DesignSystem.palette.accent.foregroundSGR }
        public static var activeName:   String { Color.ansi(.brightWhite).foregroundSGR }
        public static var inactiveName: String { DesignSystem.dim }
        public static var description:  String { DesignSystem.palette.muted.foregroundSGR }
    }

    public enum UI {
        public static let defaultPrefix       = "> "
        public static let autopilotPrefix     = "🤖 # "
        public static let shellPrefix         = "! "
        public static let shellExcludedPrefix = "!! "
    }

    public enum Scroll {
        public static var indicator: String { DesignSystem.palette.accent.foregroundSGR }
    }
}
