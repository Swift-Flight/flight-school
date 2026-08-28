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
    /// App tier only: the learner's server process is up, and this run's
    /// stream is about to end while the server keeps running. Not a claim
    /// that it's accepting connections yet — see `runApp`.
    case serverStarted
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

    /// The app tier's *build* cap. Deliberately looser than the snippet
    /// tier's 15s: PLAN §3 measured a warm Flight app incremental rebuild
    /// at 7–8s, and 15s leaves too little room above that for ordinary
    /// hardware variance. The app tier's *serve* phase has no cap at all —
    /// PLAN §5 says "app run capped per lease," and the lease is what ends
    /// it (via `/run` again, `/reset`, `/release`, or the reaper).
    static let appBuildWallClockLimit: Duration = .seconds(30)

    /// How long to wait after spawning the app before believing it stayed
    /// up. Not a readiness check — see `runApp`.
    static let appStartupGrace: Duration = .milliseconds(500)

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

    /// The app tier: build, then leave a *server* running and end the
    /// stream — the opposite of `run`'s build-and-run-to-completion.
    ///
    /// The stream deliberately ends at `.serverStarted` rather than living
    /// as long as the process. Keeping it open would mean one HTTP request
    /// held open for the whole session (up to the hard cap, an hour today)
    /// across Caddy, the server's consuming task, and the browser — every
    /// one of which has its own idle timeout, none of which this project
    /// has ever exercised at that duration. The spawned server outlives
    /// this call, owned by `WorkspaceState`, and dies when the *lease*
    /// says so: a later `/run`, `/reset`, `/release`, or the reaper.
    ///
    /// The cost, stated plainly: the learner sees build output and then
    /// nothing. Streaming a running app's logs wants its own long-lived,
    /// independently-reconnectable endpoint rather than overloading this
    /// one request to mean two different lifetimes.
    static func runApp(
        in workspace: URL, databaseURL: String?, state: WorkspaceState
    ) -> AsyncStream<RunEvent> {
        AsyncStream { continuation in
            let task = Task {
                await executeApp(
                    in: workspace, databaseURL: databaseURL, state: state,
                    continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func executeApp(
        in workspace: URL, databaseURL: String?, state: WorkspaceState,
        continuation: AsyncStream<RunEvent>.Continuation
    ) async {
        // Whatever the previous run left behind — a build still in flight,
        // or a server still bound to 8080 — goes first. Without this, a
        // second Run races the first in the same `.build` directory, and
        // the new server loses the port bind to the old one.
        await state.killRunning()

        let budget = OutputBudget(limit: outputByteLimit)

        let buildResult = await runProcess(
            executable: "/usr/bin/env", arguments: ["swift", "build"],
            workingDirectory: workspace, timeout: appBuildWallClockLimit,
            onSpawn: { await state.setRunningProcess($0) }
        ) { line in
            guard budget.consume(line.utf8.count) else { return }
            continuation.yield(.buildOutput(line))
            if budget.isExhausted { continuation.yield(.truncated) }
        }
        await state.setRunningProcess(nil)

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

        var environment = ProcessInfo.processInfo.environment
        // The template's flight.yaml binds 127.0.0.1, which is unreachable
        // from Caddy in another container. Flight's config layers env over
        // file (`FLIGHT_` + the uppercased dotted key), so this needs no
        // template edit — verified against a real run, not just the
        // mapping in FlightConfigCore.
        environment["FLIGHT_SERVER_HOST"] = "0.0.0.0"
        if let databaseURL {
            environment["DATABASE_URL"] = databaseURL
        }

        let process = Process()
        process.executableURL = workspace.appending(path: ".build/debug/App")
        process.arguments = []
        process.currentDirectoryURL = workspace
        process.environment = environment

        // The pipe has to keep being drained for as long as the server
        // lives, not just while this stream is open: an undrained pipe
        // fills its kernel buffer and then *blocks the writer*, which
        // would hang the learner's app the moment it logged enough. The
        // handler below stays installed for the process's whole lifetime
        // and yields into a continuation that has usually already
        // finished — a no-op by then, which is exactly the intent. What it
        // catches before that point is the crash-at-boot output.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let lineBuffer = LineBuffer { line in
            guard budget.consume(line.utf8.count) else { return }
            continuation.yield(.runOutput(line))
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            lineBuffer.append(data)
        }

        do {
            try process.run()
        } catch {
            continuation.yield(.runOutput("failed to start the app: \(error)"))
            continuation.yield(.exited(exitCode: -1))
            return
        }
        await state.setRunningProcess(process)

        // Not a readiness check — nothing here claims the app is accepting
        // connections, and the preview iframe's own load/retry handles
        // that gap. This catches the one failure the decoupled stream
        // would otherwise swallow silently: a server that spawns fine and
        // dies immediately (a boot-time fatalError, a bad config, a port
        // already bound), which would otherwise report `serverStarted` and
        // then simply not be there.
        try? await Task.sleep(for: appStartupGrace)
        if process.isRunning {
            continuation.yield(.serverStarted)
        } else {
            continuation.yield(.exited(exitCode: process.terminationStatus))
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
        timeout: Duration = wallClockLimit,
        onSpawn: (@Sendable (Process) async -> Void)? = nil,
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
        // Registered *after* a successful spawn, so a failed launch never
        // leaves a dead process recorded as this lease's running one.
        await onSpawn?(process)

        let exitCode = await withTaskGroup(of: ProcessOutcome?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in continuation.resume() }
                }
                return .completed(exitCode: process.terminationStatus)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
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
