import Foundation

/// Streaming/spinner state for the live response indicator.
///
/// Owns the spinner animation, elapsed counter, current partial line, and the
/// rotating thinking labels. Pure value type — the renderer composes its
/// snapshot into the footer at paint time.
struct StreamingState {
    var isGenerating: Bool = false
    var currentLine: String = ""
    var spinnerIndex: Int = 0
    var elapsedSeconds: Int = 0
    var currentThinking: String? = nil
    var pendingCount: Int = 0
    var formatter = StreamFormatter()

    static let spinnerFrames: [Character] =
        ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]

    static let thinkingSteps: [String] = [
        "Reading context...",
        "Searching files...",
        "Analyzing code structure...",
        "Planning the approach...",
        "Writing code...",
        "Reviewing changes...",
        "Checking for issues...",
        "Finalizing response...",
    ]

    /// Number of `advanceSpinner()` ticks before the rotating thinking label
    /// changes. Matches the original Renderer behavior (one step per ~25 ticks).
    static let thinkingStepDuration = 25

    var spinnerFrame: Character {
        Self.spinnerFrames[spinnerIndex % Self.spinnerFrames.count]
    }

    var thinkingLabel: String {
        if let t = currentThinking { return t }
        let idx = (elapsedSeconds / Self.thinkingStepDuration) % Self.thinkingSteps.count
        return Self.thinkingSteps[idx]
    }

    /// Elapsed time in seconds, derived from the tick counter (~10 ticks/s).
    var elapsedDisplaySeconds: Int { elapsedSeconds / 10 }

    mutating func reset() {
        currentLine = ""
        spinnerIndex = 0
        elapsedSeconds = 0
        currentThinking = nil
        formatter.reset()
    }

    mutating func advanceSpinner() {
        spinnerIndex = (spinnerIndex + 1) % Self.spinnerFrames.count
        elapsedSeconds += 1
    }
}
