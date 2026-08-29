import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// One line of output, tagged by phase — mirrors PLAN §4's event
/// vocabulary (`build_output`, `build_done`, `run_output`, `exited`).
enum RunEvent: Sendable {
    case buildOutput(String)
    case buildDone(exitCode: Int32)
    case runOutput(String)
    case exited(exitCode: Int32)
    case timedOut
    case truncated
}

/// Runs `swift build`, then — only if it succeeded — the resulting
/// binary, streaming output from both phases as it's produced.
///
/// Safety properties, all deliberate:
/// - The learner's code never becomes a command-line argument or a shell
///   string; it only ever exists as a file (`Sources/exercise/main.swift`),
///   and every process here is `swift`/the compiled binary invoked with a
///   fixed argument array — there is no shell in this path at all, so
///   there is nothing for injected shell syntax to reach.
/// - Wall-clock capped (PLAN §5: "snippet 15s") — a build or run that
///   hangs is killed, not trusted to finish.
/// - Output capped at a fixed byte budget (PLAN §5: "compiler error spam
///   is real") — a pathological `for` loop printing forever can't turn
///   into unbounded memory growth here or on the way to the browser.
enum ProcessRunner {
    static let wallClockLimit: Duration = .seconds(15)
    static let outputByteLimit = 64 * 1024

    static func run(in workspace: URL, databaseURL: String?) -> AsyncStream<RunEvent> {
        AsyncStream { continuation in
            let task = Task {
                await execute(in: workspace, databaseURL: databaseURL, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func execute(
        in workspace: URL, databaseURL: String?, continuation: AsyncStream<RunEvent>.Continuation
    ) async {
        // `onLine` below is invoked from `Pipe`'s `readabilityHandler` —
        // a GCD callback, not a Swift-concurrency task — so the budget it
        // shares across every callback has to be its own thread-safe
        // value, not a captured `var` in this function's stack frame.
        let budget = OutputBudget(limit: outputByteLimit)

        // `swift`'s real location varies by install method (Swiftly,
        // the official Docker images, apt) — resolved via PATH through
        // `env` rather than a guessed absolute path, which is genuinely
        // wrong on at least one real environment already found by
        // running this rather than assuming a location.
        let buildResult = await runProcess(
            executable: "/usr/bin/env", arguments: ["swift", "build"], workingDirectory: workspace
        ) { line in
            guard budget.consume(line.utf8.count) else { return }
            continuation.yield(.buildOutput(line))
            if budget.isExhausted { continuation.yield(.truncated) }
        }

        switch buildResult {
        case .timedOut:
            continuation.yield(.timedOut)
            return
        case .completed(let code):
            continuation.yield(.buildDone(exitCode: code))
            guard code == 0 else {
                continuation.yield(.exited(exitCode: code))
                return
            }
        }

        // DATABASE_URL only reaches the compiled binary's own process, never
        // `swift build` — the build step needs no Postgres reachability at
        // all (dependencies are already resolved into the image), matching
        // PLAN §5's "no network egress except Postgres" as tightly as
        // possible: the one process that actually needs that egress is the
        // one running for at most `wallClockLimit`, not the whole build.
        var environment = ProcessInfo.processInfo.environment
        if let databaseURL {
            environment["DATABASE_URL"] = databaseURL
        }
        let binary = workspace.appending(path: ".build/debug/exercise")
        let runResult = await runProcess(
            executable: binary.path(), arguments: [], workingDirectory: workspace, environment: environment
        ) { line in
            guard budget.consume(line.utf8.count) else { return }
            continuation.yield(.runOutput(line))
            if budget.isExhausted { continuation.yield(.truncated) }
        }

        switch runResult {
        case .timedOut:
            continuation.yield(.timedOut)
        case .completed(let code):
            continuation.yield(.exited(exitCode: code))
        }
    }

    private enum ProcessOutcome {
        case completed(exitCode: Int32)
        case timedOut
    }

    /// Runs one process to completion (or until `wallClockLimit`), calling
    /// `onLine` for each line of combined stdout/stderr as it arrives.
    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> ProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let lineBuffer = LineBuffer(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lineBuffer.append(data)
        }

        do {
            try process.run()
        } catch {
            onLine("failed to start \(executable): \(error)")
            return .completed(exitCode: -1)
        }

        let exitCode = await withTaskGroup(of: ProcessOutcome?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in continuation.resume() }
                }
                return .completed(exitCode: process.terminationStatus)
            }
            group.addTask {
                try? await Task.sleep(for: wallClockLimit)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            if case .timedOut = first {
                // `withTaskGroup` cannot return until every child task
                // finishes, `cancelAll()` included — cancellation is
                // cooperative, and the termination-watcher task above is
                // blocked on a continuation that only resumes when the
                // process actually dies. A `.terminate()` this process
                // ignores would hang this whole function forever, not
                // just miss the deadline — `forceKill` is what makes
                // "wall-clock capped" actually true.
                await forceKill(process)
            }
            group.cancelAll()
            return first
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        lineBuffer.flush()
        return exitCode ?? .completed(exitCode: process.terminationStatus)
    }

    /// SIGTERM, then SIGKILL if it doesn't take within a short grace
    /// period. Verified directly, not assumed: a process linking
    /// Hangar/SwiftNIO's dependency graph and executing macro-generated
    /// Hangar code did not exit on SIGTERM at all — not from
    /// `Process.terminate()`, and not from a bare `kill -TERM` against
    /// the same PID from the shell either, ruling out a Foundation-
    /// specific bug. SIGKILL cannot be caught, ignored, or blocked, so
    /// it's the one signal this sandbox's timeout can actually depend on.
    private static func forceKill(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 {
            guard process.isRunning else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

/// A byte budget shared across every `onLine` callback for one run —
/// those callbacks fire from `Pipe`'s `readabilityHandler`, not from
/// Swift concurrency, so the shared counter needs its own lock rather
/// than relying on actor isolation or a captured `var`.
private final class OutputBudget: @unchecked Sendable {
    private var remaining: Int
    private let lock = NSLock()
    private(set) var isExhausted = false

    init(limit: Int) { remaining = limit }

    /// Returns whether this line still fits in the budget. The line that
    /// pushes `remaining` to zero or below still counts (so the caller
    /// sees where the cutoff actually landed) but flips `isExhausted`,
    /// which the caller checks right after to emit `.truncated` once.
    func consume(_ bytes: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= bytes
        if remaining <= 0 { isExhausted = true }
        return true
    }
}

/// Accumulates raw chunks into lines — process output doesn't arrive
/// pre-split, and the event stream is line-oriented.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock()
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            lines.append(String(decoding: lineData, as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        lock.unlock()
        for line in lines { onLine(line) }
    }

    func flush() {
        lock.lock()
        let remainder = pending
        pending.removeAll()
        lock.unlock()
        guard !remainder.isEmpty else { return }
        onLine(String(decoding: remainder, as: UTF8.self))
    }
}
