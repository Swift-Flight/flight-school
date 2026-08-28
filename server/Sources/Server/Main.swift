import FlightChannels
import FlightCore
import FlightTransport
import FlightWeb
import Foundation
import PostgresNIO
import ServiceLifecycle

/// Registers the sessions/execution modules (PLAN §4). A plain struct — no
/// `service` of its own; the periodic reaper is `SessionReaperModule`,
/// separate, because a `FlightModule`'s `service` is a computed property
/// with no parameters, so a module that needs the post-freeze container to
/// build its service has to be a class that stashes it during `configure`
/// (the exact shape `FlightPresenceModule` uses) — no reason to make this
/// module a class too when it registers components and nothing else.
struct AppModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [FlightChannelsModule.self, PostgresModule.self] }

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
                broadcaster: try container.resolve(ChannelBroadcaster.self),
                postgres: try container.resolve(PostgresAdmin.self))
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

/// Owns the one admin `PostgresClient` session-database provisioning uses
/// (PLAN §3's `db` tier) — separate from `AppModule` because it needs to
/// hand a long-running `Service` (the client's own `.run()` task) to the
/// app's `ServiceGroup`, the same reason `SessionReaperModule` is a class.
/// Depended on by `AppModule` so `PostgresAdmin` is registered before
/// `SessionService` ever tries to resolve it.
///
/// `configure(_:)` only registers factories — it never calls
/// `container.resolve(_:)` directly. `Container.resolve` traps
/// ("resolve() called during the registration phase") unless it's called
/// from *inside* a factory closure, which runs later, at `freeze()`; found
/// by actually running this against a real container, not assumed from
/// `SessionBroker`'s already-correct factory-closure pattern, which this
/// module's first draft didn't follow.
final class PostgresModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [] }

    private var container: Container?

    init() {}

    func configure(_ container: Container) throws {
        self.container = container

        // Connects to Postgres's own always-present `postgres` maintenance
        // database, never the template — `CREATE`/`DROP DATABASE` cannot
        // run against a database something is currently connected to, and
        // this admin client must never be the thing holding that lock.
        container.register(PostgresClient.self, scope: .singleton) { container in
            let settings = try PostgresSettings(container)
            return PostgresClient(
                configuration: PostgresClient.Configuration(
                    host: settings.host, port: settings.port, username: settings.username,
                    password: settings.password, database: "postgres", tls: .disable))
        }

        container.register(PostgresAdmin.self, scope: .singleton) { container in
            let settings = try PostgresSettings(container)
            return PostgresAdmin(
                client: try container.resolve(PostgresClient.self),
                templateDatabase: settings.templateDatabase,
                connectionInfo: PostgresAdmin.ConnectionInfo(
                    host: settings.host, port: settings.port, username: settings.username,
                    password: settings.password))
        }
    }

    var service: (any Service)? {
        container.map { PostgresClientService(container: $0) }
    }
}

/// The four config reads both `PostgresClient` and `PostgresAdmin`'s
/// factories need, in one place so they can't drift apart from each other.
private struct PostgresSettings {
    let host: String
    let port: Int
    let username: String
    let password: String?
    let templateDatabase: String

    init(_ container: Container) throws {
        let configuration = try container.resolve(Configuration.self)
        host = try configuration.getIfPresent("postgres.host", as: String.self) ?? "postgres"
        port = try configuration.getIfPresent("postgres.port", as: Int.self) ?? 5432
        username = try configuration.getIfPresent("postgres.username", as: String.self) ?? "postgres"
        password = try configuration.getIfPresent("postgres.password", as: String.self)
        templateDatabase =
            try configuration.getIfPresent("postgres.templateDatabase", as: String.self) ?? "flight_school_seed"
    }
}

/// Keeps `PostgresClient`'s own connection-pool loop alive for the app's
/// lifetime — the same role `FlightTransport`'s HTTP service plays for
/// inbound connections, just for this one outbound admin connection.
///
/// Stores the container, not a resolved `PostgresClient`, and resolves
/// only inside `run()` — the same reason `SessionReaperService` and
/// `FlightPresenceModule`'s `PresenceService` both do this: `run()` is
/// called well after `freeze()`, while a module's `service` getter itself
/// runs in the same pre-freeze pass as `configure()` (confirmed directly
/// against a real crash: resolving eagerly in the getter traps with the
/// exact "resolve() called during the registration phase" precondition
/// PostgresModule.configure's first draft also hit).
struct PostgresClientService: Service, Sendable {
    let container: Container
    func run() async throws {
        let client = try container.resolve(PostgresClient.self)
        await client.run()
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
                    PostgresModule.self,
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
