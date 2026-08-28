import Foundation

/// Which prebuilt workspace a session is leasing, and therefore how `/run`
/// behaves (PLAN §3's execution tiers). One image carries one warm
/// workspace per tier — PLAN §4's "prebuilt workspaces, one per execution
/// tier/template" — so the pool stays undifferentiated and any runner can
/// serve any tier; the choice is made per lease, not per container.
///
/// `db` isn't a case here on purpose: it's `snippet` plus a session
/// database, which is already carried separately by `databaseURL`. What
/// distinguishes the cases below is the *process model* — build-and-run-
/// to-completion versus build-and-leave-a-server-running — not whether
/// Postgres is reachable.
enum Tier: String, Sendable {
    case snippet
    case app
}

/// This runner's own lease state. One runner container == one workspace ==
/// at most one active session at a time; the *pool* (multiple runners) is
/// what the server load-balances across, so this actor's job is
/// deliberately narrow: is this one leased, and to whom.
actor WorkspaceState {
    private(set) var leaseID: String?
    /// Which tier this lease asked for, fixed for the lease's lifetime.
    /// `nil` when unleased; defaults to `.snippet` at `lease()` for any
    /// caller that doesn't ask, so every pre-M3 client keeps working
    /// unchanged.
    private(set) var tier: Tier = .snippet
    /// This session's own database connection string, when `server`
    /// provisioned one at lease time (PLAN §3's `db` tier) — `nil` for a
    /// `snippet`-tier session that never touches Postgres. Set once, at
    /// `lease()`, and handed to every run's process environment; untouched
    /// by `reset()` — the lease, and the database behind it, both survive a
    /// reset, since only the workspace's source file goes back to pristine.
    private(set) var databaseURL: String?
    private var runningProcess: Process?

    /// Claims this runner. `nil` means it's already leased — the caller
    /// (the server) should try a different runner from the pool.
    func lease(tier: Tier, databaseURL: String?) -> String? {
        guard leaseID == nil else { return nil }
        let id = UUID().uuidString
        leaseID = id
        self.tier = tier
        self.databaseURL = databaseURL
        return id
    }

    /// Whether `candidate` is this session's real lease id — every
    /// write/run/reset/release call must present it, so a stale or
    /// guessed id from a previous session can never touch a live one.
    func isValid(_ candidate: String) -> Bool {
        leaseID != nil && leaseID == candidate
    }

    /// Records whatever process this lease's `/run` currently owns.
    ///
    /// For the snippet tier that's one short-lived thing at a time. For the
    /// app tier it's deliberately *both* phases in turn — the `swift build`
    /// while it runs, then the spawned server once it's up — because the
    /// thing `killRunning()` has to be able to kill depends on when it's
    /// called. A learner pressing Run twice in quick succession must not
    /// leave two `swift build`s racing in the same `.build` directory any
    /// more than it should leave two servers fighting over port 8080.
    func setRunningProcess(_ process: Process?) {
        runningProcess = process
    }

    /// Kills whatever's running, if anything. Idempotent.
    ///
    /// SIGTERM only — the caller decides whether to escalate. `ProcessRunner`
    /// does (its `forceKill` follows up with SIGKILL after a grace period,
    /// because a real Hangar-linked binary was observed ignoring SIGTERM
    /// entirely); this bare form is what `/reset` and `/release` use when
    /// the workspace is about to be restored anyway.
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
        tier = .snippet
        databaseURL = nil
    }
}
