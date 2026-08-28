import Foundation
import PostgresNIO

/// Provisions and tears down one Postgres database per session (PLAN §3's
/// `db` tier; PLAN §4: "`CREATE DATABASE ... TEMPLATE` per session; `DROP`
/// on scrub"). Every session gets one unconditionally, whether the
/// exercise it happens to be on needs it or not — the alternative
/// (deciding per exercise) would need the server to track which exercise
/// a session is currently viewing, which it doesn't today, and
/// `CREATE DATABASE ... TEMPLATE` is cheap enough (verified directly
/// against a real container — near-instant, unaffected by the template's
/// row count) that unconditional provisioning is simpler than that
/// bookkeeping for a real cost difference that hasn't been shown to matter.
struct PostgresAdmin: Sendable {
    struct ConnectionInfo: Sendable {
        let host: String
        let port: Int
        let username: String
        let password: String?
    }

    let client: PostgresClient
    let templateDatabase: String
    let connectionInfo: ConnectionInfo

    /// `CREATE DATABASE s_<sessionID> TEMPLATE <templateDatabase>` — the
    /// session's own isolated clone of the seeded schema. Returns the
    /// connection string the runner will hand to the learner's own
    /// snippet as `DATABASE_URL`.
    func createSessionDatabase(sessionID: String) async throws -> String {
        let name = Self.databaseName(for: sessionID)
        try await client.query(
            PostgresQuery(unsafeSQL: "CREATE DATABASE \(quote(name)) TEMPLATE \(quote(templateDatabase))"),
            logger: nil)
        return connectionURL(database: name)
    }

    /// `DROP DATABASE` — called on session release/reap. `IF EXISTS`
    /// because a session whose own provisioning failed (already surfaced
    /// as an error to the caller) must not turn this best-effort cleanup
    /// into a second one.
    func dropSessionDatabase(sessionID: String) async throws {
        let name = Self.databaseName(for: sessionID)
        try await client.query(PostgresQuery(unsafeSQL: "DROP DATABASE IF EXISTS \(quote(name))"), logger: nil)
    }

    /// Deterministic, not stored anywhere — recomputed from the session id
    /// whenever it's needed, since a Postgres database name has the same
    /// lifetime as the session it belongs to.
    private static func databaseName(for sessionID: String) -> String {
        "s_" + sessionID.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private func connectionURL(database: String) -> String {
        var components = URLComponents()
        components.scheme = "postgres"
        components.host = connectionInfo.host
        components.port = connectionInfo.port
        components.user = connectionInfo.username
        components.password = connectionInfo.password
        components.path = "/\(database)"
        return components.string!
    }

    /// Postgres DDL has no parameterized-identifier form — `CREATE
    /// DATABASE $1` isn't a thing in this or any SQL dialect — so this is
    /// genuinely raw text, not a shortcut around binding. Safe here only
    /// because the identifier is always server-generated
    /// (`databaseName(for:)`'s own output, never learner- or
    /// request-supplied text); quoting is defense in depth on top of that,
    /// not the thing making it safe.
    private func quote(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
