import Foundation
import SwiftCoderTUI

// MARK: - Stream Events

/// Events emitted by the agent's LLM stream. Defined here (not in the TUI library)
/// because the TUI has no knowledge of LLM protocols — it only receives rendered
/// calls like `appendStreamWord`, `addHistoryEntry`, etc.
public enum StreamEvent {
    case thinking(String)
    case toolCall(name: String, args: String, needsApproval: Bool)
    case toolOutput(String)
    case word(String)
    case stats(tokens: Int, tps: Double, elapsed: TimeInterval)
    case done(cancelled: Bool)
}

// MARK: - Mock streaming data for the Example app

public enum MockData {

    // MARK: Thinking notes

    static let thinkingNotes = [
        "Parsing your request...",
        "Looking up the API surface...",
        "Drafting code snippets...",
        "Reviewing best practices...",
        "Composing a clear explanation...",
    ]

    // MARK: Sample responses

    static let responses = [
        """
        Sure! Here's how you'd set up a basic HTTP server in Swift using the new \
        Swift NIO foundation:

        First, add `swift-nio` as a dependency in your Package.swift. Then create \
        an EventLoopGroup, bootstrap a ServerBootstrap, and attach your channel \
        pipeline handlers. Each inbound request arrives as a ChannelHandlerContext \
        which you respond to by writing HTTPResponseHead and HTTPResponseBody back \
        through the pipeline.

        For simple use-cases, wrapping this in an async/await layer with \
        continuation bridges keeps your business logic clean and readable.

        Want me to generate the full boilerplate for a "Hello, World" server?
        """,
        """
        Great choice! The actor model in Swift is perfect for this use-case.

        Declare your shared state as an `actor` instead of a `class`. Swift \
        guarantees that only one task can access the actor's mutable state at a \
        time — no locks needed. Callers simply `await` any method that touches \
        state, and the compiler enforces the isolation boundary at compile time.

        Key rules to remember: actors are reference types, cross-actor calls always \
        require `await`, and `nonisolated` lets you expose sync read-only computed \
        properties without a hop.
        """,
        """
        Here's a minimal example that wires everything together:

        Define a `StreamEvent` enum with cases like `.word`, `.thinking`, `.stats`, \
        and `.done`. Yield events from an `AsyncStream` producer task. On the \
        consumer side, iterate with `for await event in stream { … }`, pattern \
        match on each case, and update your UI actor accordingly.

        This pattern scales from a simple word-by-word typewriter effect all the \
        way to rich structured output with tool calls and approval flows.
        """,
    ]

    // MARK: - Demo simulation

    /// Runs the full `/demo` walkthrough against a live `Renderer`.
    public static func runDemo(renderer: Renderer) async {
        let cols = await renderer.currentCols()
        let sep = String(repeating: "─", count: min(cols, 72))
        let badgeColor = await renderer.getCurrentModeBadgeColor()

        // Streams `text` word-by-word at ~40 ms/token with spinner animation.
        func streamWords(_ text: String) async {
            await renderer.setGenerating(true)
            let spinnerTask: Task<Void, Never> = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { break }
                    await renderer.advanceSpinner()
                    await renderer.renderSpinnerTick()
                }
            }
            for token in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                await renderer.appendStreamWord(token)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            await renderer.flushStreamLine()
            spinnerTask.cancel()
            await renderer.setGenerating(false)
            await renderer.renderFooter()
        }

        // ── Scene 0 — banner ────────────────────────────────────────────────
        await renderer.printScrollLine("\(DesignSystem.dim)\(sep)\(DesignSystem.reset)")
        await renderer.printScrollLine("\(DesignSystem.bold)── /demo: Interactive chat simulation ──\(DesignSystem.reset)")
        await renderer.printScrollLine("\(DesignSystem.darkGray)Simulating a multi-turn coding assistant session...\(DesignSystem.reset)")
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 1 — multiline user message ────────────────────────────────
        let user1 = SessionEntry(role: .user, content: """
            Create a new Swift file that defines a `Color` extension
            with a `hex(_ string: String) -> Color` factory method.
            Also add a unit test for it.
            """)
        await renderer.addHistoryEntry(user1)
        await renderer.printScrollLine(user1.render())
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 2 — thinking + spinner ────────────────────────────────────
        let think1 = SessionEntry(role: .thinking(badgeColor: badgeColor), content: "Analysing the request...")
        await renderer.addHistoryEntry(think1)
        await renderer.printScrollLine(think1.render())
        await renderer.setThinking("Analysing the request...")
        await renderer.setGenerating(true)
        await renderer.renderFooter()
        let demoSpinner: Task<Void, Never> = Task {
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                await renderer.advanceSpinner()
                await renderer.renderSpinnerTick()
            }
        }
        await demoSpinner.value
        await renderer.setGenerating(false)
        await renderer.setActiveFile("Sources/SwiftCoderTUI/Color.swift")
        await renderer.renderFooter()
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 3 — tool call: read_file ──────────────────────────────────
        let readCall = SessionEntry(role: .toolCall, content: "read_file Sources/SwiftCoderTUI/Color.swift")
        await renderer.addHistoryEntry(readCall)
        await renderer.printScrollLine(readCall.render())
        try? await Task.sleep(nanoseconds: 400_000_000)

        let readOutput = SessionEntry(role: .toolOutput, content: """
            // Color.swift (258 lines)
            public enum Color: Sendable, Hashable {
                case ansi(ANSIColor)
                case xterm(Int)
                case rgb(UInt8, UInt8, UInt8)
                ...
            }
            """)
        await renderer.addHistoryEntry(readOutput)
        await renderer.printScrollLine(readOutput.render())
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 4 — tool call: create_file (approval → auto-accept) ───────
        let createCall = SessionEntry(role: .toolCall, content: "create_file Sources/SwiftCoderTUI/ColorHex.swift")
        await renderer.addHistoryEntry(createCall)
        await renderer.printScrollLine(createCall.render())
        await renderer.requestApproval(tool: "create_file", args: "Sources/SwiftCoderTUI/ColorHex.swift")
        try? await Task.sleep(nanoseconds: 800_000_000)
        await renderer.clearApproval()
        await renderer.printScrollLine("\(DesignSystem.dim)(auto-accepted for demo)\(DesignSystem.reset)")
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 5 — streamed response: code creation ──────────────────────
        await streamWords("""
            I'll create the extension in a new file and add a unit test.

            **ColorHex.swift** (new file):

            ```swift
            extension Color {
            /// Creates a Color from a hex string like "#FF6B6B" or "FF6B6B".
            public static func hex(_ string: String) -> Color {
            var s = string.hasPrefix("#") ? String(string.dropFirst()) : string
            guard s.count == 6, let value = UInt32(s, radix: 16) else { return .ansi(.white) }
            return .rgb(UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
            }
            }
            ```

            **ColorHexTests.swift** (new test):

            ```swift
            func testHexParsing() {
            XCTAssertEqual(Color.hex("#FF0000"), Color.rgb(255, 0, 0))
            XCTAssertEqual(Color.hex("00FF00"), Color.rgb(0, 255, 0))
            }
            ```

            Both files are ready. Run `swift test` to verify.
            """)
        let stats1 = SessionEntry(role: .stats, content: "", tokenCount: 120, tokensPerSecond: 32.0, elapsed: 3.7)
        await renderer.addHistoryEntry(stats1)
        await renderer.printScrollLine(stats1.render())
        await renderer.printScrollLine("")
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 6 — queue demo ─────────────────────────────────────────────
        await renderer.printScrollLine("\(DesignSystem.dim)Queuing a follow-up prompt...\(DesignSystem.reset)")
        await renderer.setPendingCount(1)
        try? await Task.sleep(nanoseconds: 600_000_000)
        await renderer.setPendingCount(0)
        await renderer.printScrollLine(
            "\(DesignSystem.darkGray)Follow-up processed: \"Add a `lerp` overload that accepts hex strings\"\(DesignSystem.reset)"
        )
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 7 — second user message ────────────────────────────────────
        let user2 = SessionEntry(role: .user, content: "Now show a diff for the edit you'd make.")
        await renderer.addHistoryEntry(user2)
        await renderer.printScrollLine(user2.render())
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 8 — tool call: edit_file (approval → auto-accept) ──────────
        let editCall = SessionEntry(role: .toolCall, content: "edit_file Sources/SwiftCoderTUI/Color.swift")
        await renderer.addHistoryEntry(editCall)
        await renderer.printScrollLine(editCall.render())
        await renderer.requestApproval(tool: "edit_file", args: "Sources/SwiftCoderTUI/Color.swift")
        try? await Task.sleep(nanoseconds: 800_000_000)
        await renderer.clearApproval()
        await renderer.printScrollLine("\(DesignSystem.dim)(auto-accepted for demo)\(DesignSystem.reset)")
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 9 — streamed diff response ─────────────────────────────────
        await streamWords("""
            Here's the minimal edit to `Color.swift`:

            ```diff
            --- a/Sources/SwiftCoderTUI/Color.swift
            +++ b/Sources/SwiftCoderTUI/Color.swift
            @@ -115,6 +115,13 @@ public enum Color {
             public static func lerp(_ a: Color, _ b: Color, phase: Double) -> Color {
            +
            +    /// Lerp from two hex strings, e.g. `Color.lerp("#FF0000", "#0000FF", phase: 0.5)`.
            +    public static func lerp(_ aHex: String, _ bHex: String, phase: Double) -> Color {
            +        lerp(hex(aHex), hex(bHex), phase: phase)
            +    }
             }
            ```

            The change adds 4 lines. No existing logic is modified.
            """)
        let stats2 = SessionEntry(role: .stats, content: "", tokenCount: 85, tokensPerSecond: 28.0, elapsed: 3.1)
        await renderer.addHistoryEntry(stats2)
        await renderer.printScrollLine(stats2.render())
        await renderer.printScrollLine("")
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 10 — Markdown showcase ─────────────────────────────────────
        await renderer.printScrollLine("\(DesignSystem.dim)Rendering a Markdown summary...\(DesignSystem.reset)")
        let md = """
            ## Session Summary

            The new **ColorHex** extension provides *convenient* hex colour parsing.

            ```swift
            let red = Color.hex("#FF0000")
            ```

            - `hex(_:)` parses 6-char hex strings
            - Supports `#`-prefixed and bare strings
            - Falls back to `.ansi(.white)` on invalid input

            [swift-markdown](https://github.com/apple/swift-markdown)

            > All existing Color cases remain unchanged. No breaking changes.

            | Method | Returns |
            |--------|---------|
            | `hex("#FF0000")` | `.rgb(255, 0, 0)` |
            | `hex("00FF00")` | `.rgb(0, 255, 0)` |

            ---
            """
        let mdLines = MarkdownRenderer(width: min(cols, 72)).render(md).components(separatedBy: "\n")
        for line in mdLines { await renderer.printScrollLine(line) }
        try? await Task.sleep(nanoseconds: 400_000_000)

        // ── Scene 11 — done banner ───────────────────────────────────────────
        await renderer.printScrollLine("\(DesignSystem.dim)\(sep)\(DesignSystem.reset)")
        await renderer.printScrollLine(
            "\(DesignSystem.bold)\(DesignSystem.green)Demo complete. Try typing a real prompt!\(DesignSystem.reset)"
        )
        await renderer.renderFooter()
    }

    // MARK: - Stream a mock response

    /// Produce an `AsyncStream<StreamEvent>` that simulates an AI reply.
    /// If `prompt` contains the word "tool", a simulated tool call is injected.
    public static func stream(for prompt: String) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let task = Task {
                // Optionally inject a tool call
                if prompt.lowercased().contains("tool") {
                    continuation.yield(.thinking("Selecting the right tool..."))
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    continuation.yield(.toolCall(
                        name: "read_file",
                        args: "Sources/SwiftCoderTUI/AppConfig.swift",
                        needsApproval: true
                    ))
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    continuation.yield(.toolOutput(
                        "// AppConfig.swift — 142 lines read successfully."
                    ))
                }

                // Emit a thinking note
                let note = thinkingNotes.randomElement()!
                continuation.yield(.thinking(note))
                try? await Task.sleep(nanoseconds: 500_000_000)

                guard !Task.isCancelled else {
                    continuation.yield(.done(cancelled: true))
                    continuation.finish()
                    return
                }

                // Stream response word by word
                let response = responses.randomElement()!
                let words = response.split(separator: " ", omittingEmptySubsequences: false)
                let startTime = Date()
                var wordCount = 0

                for word in words {
                    guard !Task.isCancelled else {
                        let elapsed = Date().timeIntervalSince(startTime)
                        let tps = wordCount > 0 ? Double(wordCount) / elapsed : 0
                        continuation.yield(.stats(tokens: wordCount, tps: tps, elapsed: elapsed))
                        continuation.yield(.done(cancelled: true))
                        continuation.finish()
                        return
                    }
                    continuation.yield(.word(String(word)))
                    wordCount += 1
                    let delay = UInt64.random(in: 25_000_000...70_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let tps = wordCount > 0 ? Double(wordCount) / elapsed : 0
                continuation.yield(.stats(tokens: wordCount, tps: tps, elapsed: elapsed))
                continuation.yield(.done(cancelled: false))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
