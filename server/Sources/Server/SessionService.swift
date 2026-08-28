import FlightChannels
import Foundation

/// The execution module (PLAN §4): bridges HTTP session/run requests to the
/// leased runner and fans build/run output out to `session:<id>` channel
/// subscribers. No HTTP response ever blocks on a full run finishing —
/// `run(sessionID:)` dispatches the runner call and returns immediately,
/// because the actual output arrives over the channel the browser is
/// expected to have already joined, not the HTTP response body.
struct SessionService: Sendable {
    let broker: SessionBroker
    let client: RunnerClient
    let broadcaster: ChannelBroadcaster
    let postgres: PostgresAdmin

    static func topic(for sessionID: String) -> String { "session:\(sessionID)" }

    /// Reuses `existingSessionID` if it's still live; otherwise claims a
    /// runner from the pool, provisions this session's own database
    /// (PLAN §3's `db` tier — every session gets one, see
    /// `PostgresAdmin`'s doc comment for why that's simpler than deciding
    /// per exercise), leases the runner over HTTP with that database's
    /// connection string, and mints a fresh session id. The session id
    /// itself is the only credential a joining socket presents (see
    /// SessionChannel) — consistent with v1 having no accounts at all
    /// (PLAN §1): knowing the id is exactly as much proof of ownership as
    /// the `HttpOnly` cookie it travels in.
    func getOrCreateSession(existingSessionID: String?, tier: Tier = .snippet) async throws -> String {
        if let id = existingSessionID, let existing = await broker.touch(sessionID: id) {
            // A live session is only reusable for the tier it was leased
            // for: the runner picked its workspace at `/lease` time and
            // can't switch mid-lease. Without this check, a learner
            // arriving at a Part 1 (app) exercise still holding a Part 2
            // (snippet) session cookie would silently get a snippet
            // workspace — their code would land in the wrong project and
            // the failure would look like a compiler error, not a
            // plumbing bug. Tear the old one down and start fresh.
            if existing.tier == tier {
                return id
            }
            await endSession(sessionID: id)
        }
        guard let runnerBaseURL = await broker.claimRunner() else {
            throw SessionBroker.BrokerError.poolExhausted
        }
        let sessionID = UUID().uuidString
        do {
            let databaseURL = try await postgres.createSessionDatabase(sessionID: sessionID)
            do {
                let leaseID = try await client.lease(
                    baseURL: runnerBaseURL, tier: tier, databaseURL: databaseURL)
                await broker.attach(
                    sessionID: sessionID,
                    lease: .init(runnerBaseURL: runnerBaseURL, leaseID: leaseID, tier: tier))
                return sessionID
            } catch {
                // The database exists but the runner never accepted it —
                // drop it rather than leaking a database with nothing
                // that will ever reap it (the broker never learned this
                // session id, so SessionReaperService can't find it either).
                try? await postgres.dropSessionDatabase(sessionID: sessionID)
                throw error
            }
        } catch {
            await broker.unclaim(runnerBaseURL)
            throw error
        }
    }

    /// Where this session's preview iframe should point, matching the
    /// Caddyfile's `/preview/<runner-service-name>/*` routes.
    ///
    /// Keyed by the runner's hostname rather than a position in the pool:
    /// `SessionBroker`'s free list reorders as runners are claimed and
    /// released, so an index would drift, while the hostname is what Caddy
    /// actually routes on. `nil` if the session is gone.
    func previewPath(sessionID: String) async -> String? {
        guard let lease = await broker.touch(sessionID: sessionID),
            let host = URLComponents(string: lease.runnerBaseURL)?.host
        else { return nil }
        return "/preview/\(host)/"
    }

    /// App tier: a set of files keyed by path relative to the project
    /// root. The runner enforces which of those paths are writable — see
    /// `RunnerController.appEditableRoots`.
    func writeFiles(sessionID: String, files: [String: String]) async throws {
        guard let lease = await broker.touch(sessionID: sessionID) else {
            throw SessionBroker.BrokerError.unknownSession
        }
        try await client.writeFiles(
            baseURL: lease.runnerBaseURL, leaseID: lease.leaseID, files: files)
    }

    func write(sessionID: String, content: String) async throws {
        guard let lease = await broker.touch(sessionID: sessionID) else {
            throw SessionBroker.BrokerError.unknownSession
        }
        try await client.write(baseURL: lease.runnerBaseURL, leaseID: lease.leaseID, content: content)
    }

    func reset(sessionID: String) async throws {
        guard let lease = await broker.touch(sessionID: sessionID) else {
            throw SessionBroker.BrokerError.unknownSession
        }
        try await client.reset(baseURL: lease.runnerBaseURL, leaseID: lease.leaseID)
    }

    /// Kicks the run off in a detached task and returns as soon as the
    /// session's lease is confirmed live — see the type doc. A failure
    /// calling the runner itself (not a build/run failure — those arrive
    /// as ordinary `build_output`/`exited` events) surfaces as a
    /// `run_error` event on the same topic rather than a channel-protocol
    /// `flight:error`, which is reserved for join/handle failures, not
    /// side-channel work triggered outside the channel entirely.
    func run(sessionID: String) async throws {
        guard let lease = await broker.touch(sessionID: sessionID) else {
            throw SessionBroker.BrokerError.unknownSession
        }
        let topic = Self.topic(for: sessionID)
        let broadcaster = broadcaster
        let client = client
        let tier = lease.tier
        Task {
            do {
                try await client.run(
                    baseURL: lease.runnerBaseURL, leaseID: lease.leaseID, tier: tier
                ) { event, data in
                    await broadcaster.broadcast(topic: topic, event: event, payload: .object(["data": .string(data)]))
                }
            } catch {
                await broadcaster.broadcast(
                    topic: topic, event: "run_error",
                    payload: .object(["message": .string(String(describing: error))]))
            }
        }
    }

    /// An explicit end to a session (as opposed to idle-timeout reaping,
    /// which `SessionReaperService` drives) — releases the runner back to
    /// the pool right away instead of waiting out the idle timeout.
    func endSession(sessionID: String) async {
        guard let lease = await broker.detach(sessionID: sessionID) else { return }
        try? await client.release(baseURL: lease.runnerBaseURL, leaseID: lease.leaseID)
        try? await postgres.dropSessionDatabase(sessionID: sessionID)
    }
}
