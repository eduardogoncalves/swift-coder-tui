import Foundation

// MARK: - CaffeinateMode

public enum CaffeinateMode: Equatable, Sendable {
    /// Prevents idle sleep and system sleep (`caffeinate -i -s`).
    case on
    /// Prevents idle, system, and display sleep (`caffeinate -i -s -d`).
    case busy
    /// Prevents sleep for a fixed number of seconds (`caffeinate -i -s -t N`).
    case duration(seconds: Int)
}

// MARK: - CaffeinateManager

/// Manages a background `caffeinate` process to prevent system sleep.
///
/// Only functional on macOS. On other platforms all operations are no-ops and
/// ``isActive`` always returns `false`.
///
/// ```swift
/// let manager = CaffeinateManager()
/// await manager.enable(mode: .on)       // prevent idle + system sleep
/// await manager.enable(mode: .busy)     // prevent display sleep too
/// await manager.enable(mode: .duration(seconds: 1800))  // 30 minutes
/// await manager.disable()               // allow sleep again
/// ```
public actor CaffeinateManager {

    private var process: Process?

    /// The currently active keep-alive mode, or `nil` when inactive.
    public private(set) var activeMode: CaffeinateMode?

    /// `true` while a caffeinate process is running.
    public var isActive: Bool { activeMode != nil }

    public init() {}

    // MARK: - Public API

    /// Starts a caffeinate session, replacing any active one.
    public func enable(mode: CaffeinateMode = .on) {
        terminate()
        #if os(macOS)
        let args: [String]
        switch mode {
        case .on:
            args = ["-i", "-s"]
        case .busy:
            args = ["-i", "-s", "-d"]
        case .duration(let seconds):
            args = ["-i", "-s", "-t", "\(seconds)"]
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = args
        p.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }
        do {
            try p.run()
            process = p
            activeMode = mode
        } catch {
            // caffeinate unavailable — silently remain inactive
        }
        #endif
    }

    /// Terminates the active caffeinate session, allowing the system to sleep normally.
    public func disable() {
        terminate()
    }

    // MARK: - Private helpers

    private func terminate() {
        process?.terminate()
        process = nil
        activeMode = nil
    }

    private func handleTermination() {
        if process?.isRunning == false {
            process = nil
            activeMode = nil
        }
    }

    // MARK: - Status

    /// Human-readable description of the current state for display in the TUI.
    public var statusDescription: String {
        switch activeMode {
        case .none:
            return "off"
        case .on:
            return "on (idle + system sleep prevented)"
        case .busy:
            return "busy (idle + system + display sleep prevented)"
        case .duration(let seconds):
            return "on for \(formatDuration(seconds))"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds % 3_600 == 0 { return "\(seconds / 3_600)h" }
        if seconds % 60    == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}
