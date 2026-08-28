import Foundation

/// This runner's own lease state. One runner container == one workspace ==
/// at most one active session at a time; the *pool* (multiple runners) is
/// what the server load-balances across, so this actor's job is
/// deliberately narrow: is this one leased, and to whom.
actor WorkspaceState {
    private(set) var leaseID: String?
    private var runningProcess: Process?

    /// Claims this runner. `nil` means it's already leased — the caller
    /// (the server) should try a different runner from the pool.
    func lease() -> String? {
        guard leaseID == nil else { return nil }
        let id = UUID().uuidString
        leaseID = id
        return id
    }

    /// Whether `candidate` is this session's real lease id — every
    /// write/run/reset/release call must present it, so a stale or
    /// guessed id from a previous session can never touch a live one.
    func isValid(_ candidate: String) -> Bool {
        leaseID != nil && leaseID == candidate
    }

    func setRunningProcess(_ process: Process?) {
        runningProcess = process
    }

    /// Kills whatever's running, if anything. Idempotent.
    func killRunning() {
        if let runningProcess, runningProcess.isRunning {
            runningProcess.terminate()
        }
        runningProcess = nil
    }

    /// Ends the lease entirely — the runner becomes available for a new
    /// `lease()` immediately after.
    func release() {
        killRunning()
        leaseID = nil
    }
}
