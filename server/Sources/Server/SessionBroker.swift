import Foundation

/// Pure in-memory pool/session state (PLAN §4's "sessions" module): which
/// runners are free, which are on lease to which session, and when a
/// session was last touched. No I/O here — `RunnerClient` calls the runner
/// over HTTP, `SessionService` composes the two so a lease is never
/// recorded here until the runner has actually confirmed it. An actor
/// because it's mutated from concurrent request handlers and the
/// background reaper alike.
actor SessionBroker {
    struct RunnerLease: Sendable {
        let runnerBaseURL: String
        let leaseID: String
    }

    enum BrokerError: Error, CustomStringConvertible, Sendable {
        case poolExhausted
        case unknownSession

        var description: String {
            switch self {
            case .poolExhausted: return "no runner available in the pool right now"
            case .unknownSession: return "unknown or expired session"
            }
        }
    }

    private struct Entry {
        var lease: RunnerLease
        var lastTouched: ContinuousClock.Instant
        let createdAt: ContinuousClock.Instant
    }

    private var freeRunners: [String]
    private var sessions: [String: Entry] = [:]
    private let idleTimeout: Duration
    private let hardCap: Duration

    init(runnerPool: [String], idleTimeout: Duration, hardCap: Duration) {
        self.freeRunners = runnerPool
        self.idleTimeout = idleTimeout
        self.hardCap = hardCap
    }

    /// Takes one runner out of the free pool. `nil` means every runner is
    /// already leased — the caller decides how to surface that (PLAN §4:
    /// "honest queue UI"). Returns the URL, not a lease — the caller still
    /// has to call the runner's own `/lease` before `attach` records it.
    func claimRunner() -> String? {
        guard !freeRunners.isEmpty else { return nil }
        return freeRunners.removeFirst()
    }

    /// Undoes `claimRunner` when the runner's own `/lease` call failed —
    /// the runner was never actually leased, so it goes straight back.
    func unclaim(_ runnerBaseURL: String) {
        freeRunners.append(runnerBaseURL)
    }

    /// Records a session now that the runner has confirmed the lease.
    func attach(sessionID: String, lease: RunnerLease) {
        let now = ContinuousClock.now
        sessions[sessionID] = Entry(lease: lease, lastTouched: now, createdAt: now)
    }

    /// The session's current lease, refreshing its idle clock — every
    /// request that reaches a live session counts as activity. `nil` if the
    /// session was never created or has already been reaped.
    func touch(sessionID: String) -> RunnerLease? {
        guard var entry = sessions[sessionID] else { return nil }
        entry.lastTouched = .now
        sessions[sessionID] = entry
        return entry.lease
    }

    /// True without refreshing the idle clock — the channel join gate
    /// checks liveness on every join attempt, which shouldn't itself count
    /// as the activity that keeps a session alive.
    func isLive(sessionID: String) -> Bool {
        sessions[sessionID] != nil
    }

    /// Ends a session explicitly (an intentional release, not idle expiry),
    /// freeing its runner back to the pool immediately.
    func detach(sessionID: String) -> RunnerLease? {
        guard let entry = sessions.removeValue(forKey: sessionID) else { return nil }
        freeRunners.append(entry.lease.runnerBaseURL)
        return entry.lease
    }

    /// Sweeps every session past the idle timeout or hard cap, freeing
    /// their runners back to the pool and returning what was reaped so the
    /// caller can tell the runner to scrub and notify anyone still
    /// connected. Called periodically by `SessionReaperService`.
    func reapExpired() -> [(sessionID: String, lease: RunnerLease)] {
        let now = ContinuousClock.now
        var expired: [(sessionID: String, lease: RunnerLease)] = []
        for (id, entry) in sessions {
            if now - entry.lastTouched > idleTimeout || now - entry.createdAt > hardCap {
                expired.append((id, entry.lease))
            }
        }
        for (id, lease) in expired {
            sessions.removeValue(forKey: id)
            freeRunners.append(lease.runnerBaseURL)
        }
        return expired
    }
}
