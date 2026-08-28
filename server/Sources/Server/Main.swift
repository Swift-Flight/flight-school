import FlightChannels
import FlightCore
import FlightTransport
import FlightWeb
import Foundation
import ServiceLifecycle

/// Registers the sessions/execution modules (PLAN §4). A plain struct — no
/// `service` of its own; the periodic reaper is `SessionReaperModule`,
/// separate, because a `FlightModule`'s `service` is a computed property
/// with no parameters, so a module that needs the post-freeze container to
/// build its service has to be a class that stashes it during `configure`
/// (the exact shape `FlightPresenceModule` uses) — no reason to make this
/// module a class too when it registers components and nothing else.
struct AppModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [FlightChannelsModule.self] }

    func configure(_ container: Container) throws {
        container.register(SessionBroker.self, scope: .singleton) { container in
            let configuration = try container.resolve(Configuration.self)
            let runnerPool = configuration.reader.stringArray(forKey: "runners.pool", default: [])
            let idleTimeout = try configuration.getIfPresent("session.idleTimeoutSeconds", as: Int.self) ?? 600
            let hardCap = try configuration.getIfPresent("session.hardCapSeconds", as: Int.self) ?? 3600
            return SessionBroker(
                runnerPool: runnerPool,
                idleTimeout: .seconds(idleTimeout),
                hardCap: .seconds(hardCap))
        }
        container.register(RunnerClient.self, scope: .singleton) { _ in RunnerClient() }
        container.register(SessionService.self, scope: .singleton) { container in
            SessionService(
                broker: try container.resolve(SessionBroker.self),
                client: try container.resolve(RunnerClient.self),
                broadcaster: try container.resolve(ChannelBroadcaster.self))
        }

        container.registerChannel("session:*") { container in
            SessionChannel(broker: try container.resolve(SessionBroker.self))
        }
        // No `authenticate` closure — v1 has no accounts (PLAN §1); the
        // session id itself is the only credential (see SessionService).
        container.registerChannelSocket("/socket")

        try flightRegisterAll(container)
    }
}

/// Separate from `AppModule` because its `service` needs the container
/// post-freeze (to resolve `SessionBroker`/`RunnerClient`/
/// `ChannelBroadcaster` once every module has configured) — the same
/// reason `FlightPresenceModule` is a class rather than a struct.
final class SessionReaperModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [AppModule.self] }

    private var container: Container?

    init() {}

    func configure(_ container: Container) throws {
        self.container = container
    }

    var service: (any Service)? {
        container.map { SessionReaperService(container: $0) }
    }
}

@main
struct Main {
    static func main() async {
        do {
            let configuration = try Configuration.load()
            try await Flight.bootstrap(
                configuration: configuration,
                modules: [
                    FlightWebModule<FlightTransport>.self,
                    AppModule.self,
                    SessionReaperModule.self,
                ])
        } catch {
            FileHandle.standardError.write(
                Data("server failed to start: \(String(reflecting: error))\n".utf8))
            exit(1)
        }
    }
}
