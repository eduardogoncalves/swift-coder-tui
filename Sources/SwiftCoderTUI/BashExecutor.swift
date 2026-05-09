import Foundation
import os

// MARK: - Public types

public struct BashResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    /// `true` when output was cut short by a `lineLimit`.
    public let truncated: Bool

    /// Convenience: stdout followed by stderr (non-empty parts joined with a newline).
    public var output: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum BashExecutorError: Error, Sendable {
    case timeout
    case launchFailed(Error)
}

// MARK: - BashExecutor actor

/// Async, non-blocking shell executor.  Process spawns are serialised through
/// the actor; stdout and stderr are streamed as lines arrive rather than
/// buffered until the process exits.
public actor BashExecutor {
    /// Shell binary used to interpret `command` strings.
    ///
    /// Resolved once at process start using `$SHELL` if it points to an
    /// existing executable, otherwise falling back to `/bin/sh` which is
    /// guaranteed to exist on every POSIX host.  The previous hardcoded
    /// `/bin/zsh` was Darwin-specific and broke on stock Linux installs.
    static let shellPath: String = {
        if let env = ProcessInfo.processInfo.environment["SHELL"],
           !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        return "/bin/sh"
    }()

    public init() {}

    /// Runs `command` and returns the collected `BashResult` when the process exits.
    /// - Parameters:
    ///   - command: Shell command passed to ``BashExecutor/shellPath`` via `-c`
    ///     (resolved from `$SHELL`, falling back to `/bin/sh`).
    ///   - timeout: Optional wall-clock timeout.  The process is sent SIGTERM and
    ///     `BashExecutorError.timeout` is thrown if the deadline is exceeded.
    ///   - lineLimit: Optional maximum number of stdout lines to collect. The process
    ///     is terminated once the limit is reached; `BashResult.truncated` will be `true`.
    public func run(_ command: String, timeout: Duration? = nil, lineLimit: Int? = nil) async throws -> BashResult {
        let stdout = _LineCollector()
        let stderr = _LineCollector()
        var didTruncate = false

        if let limit = lineLimit {
            // Streaming path: terminate the process once we hit the line cap.
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: Self.shellPath)
            process.arguments = ["-c", command]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
            process.terminationHandler = { p in
                exitContinuation.yield(p.terminationStatus)
                exitContinuation.finish()
            }
            do {
                try process.run()
            } catch {
                throw BashExecutorError.launchFailed(error)
            }
            enum Outcome: Sendable { case completed, timedOut }
            let outcome: Outcome = await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    await withTaskGroup(of: Void.self) { inner in
                        inner.addTask {
                            var count = 0
                            do {
                                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                                    stdout.append(line)
                                    count += 1
                                    if count >= limit {
                                        stdout.setTruncated()
                                        process.terminate()
                                        break
                                    }
                                }
                            } catch {}
                        }
                        inner.addTask {
                            do {
                                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                                    stderr.append(line)
                                }
                            } catch {}
                        }
                    }
                    return .completed
                }
                if let duration = timeout {
                    group.addTask {
                        try? await Task.sleep(for: duration)
                        return Task.isCancelled ? .completed : .timedOut
                    }
                }
                let result = await group.next() ?? .completed
                group.cancelAll()
                return result
            }

            if outcome == .timedOut {
                process.terminate()
                for await _ in exitStream {}
                throw BashExecutorError.timeout
            }
            for await _ in exitStream {}
            didTruncate = stdout.wasTruncated
            return BashResult(exitCode: process.terminationStatus,
                              stdout: stdout.joined(),
                              stderr: stderr.joined(),
                              truncated: didTruncate)
        }

        let exitCode = try await runStreaming(
            command,
            timeout: timeout,
            onStdoutLine: { line in stdout.append(line) },
            onStderrLine: { line in stderr.append(line) }
        )

        return BashResult(
            exitCode: exitCode,
            stdout: stdout.joined(),
            stderr: stderr.joined(),
            truncated: false
        )
    }

    /// Streams stdout/stderr lines to closures as they arrive and returns the exit code.
    ///
    /// Lines are split on `\n`.  The closures may be called from any thread and
    /// must be `Sendable`.
    public func runStreaming(
        _ command: String,
        timeout: Duration? = nil,
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: Self.shellPath)
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Bridge process termination to an AsyncStream so we can await it
        // without blocking a cooperative thread.
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { p in
            exitContinuation.yield(p.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw BashExecutorError.launchFailed(error)
        }

        // Race IO-drain against optional timeout.
        enum Outcome: Sendable { case completed, timedOut }

        let outcome: Outcome = await withTaskGroup(of: Outcome.self) { group in
            // Drain stdout and stderr concurrently using FileHandle.bytes async sequence.
            group.addTask {
                await withTaskGroup(of: Void.self) { inner in
                    inner.addTask {
                        do {
                            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                                onStdoutLine(line)
                            }
                        } catch {}
                    }
                    inner.addTask {
                        do {
                            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                                onStderrLine(line)
                            }
                        } catch {}
                    }
                }
                return .completed
            }

            if let duration = timeout {
                group.addTask {
                    try? await Task.sleep(for: duration)
                    // Only report timeout if sleep completed (not cancelled).
                    return Task.isCancelled ? .completed : .timedOut
                }
            }

            let result = await group.next() ?? .completed
            group.cancelAll()
            return result
        }

        if outcome == .timedOut {
            process.terminate()
            // Drain exit stream to release resources.
            for await _ in exitStream {}
            throw BashExecutorError.timeout
        }

        // Wait for the process to exit (non-blocking suspension).
        var code: Int32 = 0
        for await c in exitStream { code = c }
        return code
    }
}

// MARK: - Private helpers

/// Thread-safe string-line accumulator for use with `@Sendable` closures.
private final class _LineCollector: @unchecked Sendable {
    private struct State {
        var lines: [String] = []
        var truncated = false
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    func append(_ line: String) {
        stateLock.withLock { $0.lines.append(line) }
    }

    func setTruncated() {
        stateLock.withLock { $0.truncated = true }
    }

    var wasTruncated: Bool {
        stateLock.withLock { $0.truncated }
    }

    func joined() -> String {
        stateLock.withLock { $0.lines.joined(separator: "\n") }
    }
}
