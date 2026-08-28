import FlightChannels
import FlightCore
import Logging
import ServiceLifecycle

/// The periodic half of the sessions module (PLAN §4: "idle TTL reaper").
/// Every `reapIntervalSeconds`, sweeps sessions past the idle timeout or
/// hard cap, tells each one's runner to release the lease (scrubbing its
/// workspace back to pristine), and pushes a `session_expired` event so a
/// still-connected browser learns its session is gone rather than
/// silently getting 404s on its next request.
struct SessionReaperService: Service, Sendable {
    let container: Container
    let logger: Logger

    init(container: Container, logger: Logger = Logger(label: "flight-school.server.reaper")) {
        self.container = container
        self.logger = logger
    }

    func run() async throws {
        let broker = try container.resolve(SessionBroker.self)
        let client = try container.resolve(RunnerClient.self)
        let broadcaster = try container.resolve(ChannelBroadcaster.self)
        let configuration = try container.resolve(Configuration.self)
        let interval = try configuration.getIfPresent("session.reapIntervalSeconds", as: Int.self) ?? 30

        await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: .seconds(interval))) != nil else { return }
                let expired = await broker.reapExpired()
                guard !expired.isEmpty else { continue }
                logger.info("reaped \(expired.count) idle session(s)")
                for (sessionID, lease) in expired {
                    do {
                        try await client.release(baseURL: lease.runnerBaseURL, leaseID: lease.leaseID)
                    } catch {
                        logger.error("failed to release runner \(lease.runnerBaseURL) for reaped session \(sessionID): \(error)")
                    }
                    await broadcaster.broadcast(
                        topic: SessionService.topic(for: sessionID), event: "session_expired")
                }
            }
        }
    }
}
