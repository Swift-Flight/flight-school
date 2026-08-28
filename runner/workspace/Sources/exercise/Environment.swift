// Never overwritten by a learner's write — only Sources/exercise/main.swift
// is (see RunnerController.write). This is the db tier's one line of setup:
// `let repo = try await makeRepo()`. Everything else — parsing the
// connection string, starting PostgresClient's background task — happens
// here, once, so a db-tier exercise's own snippet starts from a working
// `Repo` the way the guides already show it, instead of repeating
// PostgresClient bootstrap boilerplate in every single starting snippet.
import Foundation
import Hangar

enum EnvironmentError: Error, CustomStringConvertible {
    case noDatabaseConfigured
    var description: String {
        "DATABASE_URL is not set for this session — this exercise needs the db tier, and this session was leased without one."
    }
}

/// `DATABASE_URL` is set by the runner supervisor only for a session the
/// server provisioned a database for (PLAN §3's `db` tier) — absent
/// entirely for a `snippet`-tier session, which is exactly why this throws
/// rather than silently returning some inert placeholder: a snippet that
/// calls `makeRepo()` without a database is a real error to surface, not
/// something to paper over.
func makeRepo() async throws -> Repo {
    guard let raw = ProcessInfo.processInfo.environment["DATABASE_URL"],
        let components = URLComponents(string: raw)
    else {
        throw EnvironmentError.noDatabaseConfigured
    }
    let configuration = PostgresClient.Configuration(
        host: components.host ?? "127.0.0.1",
        port: components.port ?? 5432,
        username: components.user ?? "postgres",
        password: components.password,
        database: components.path.isEmpty ? nil : String(components.path.dropFirst()),
        tls: .disable)
    let client = PostgresClient(configuration: configuration)
    // Never explicitly stopped — this process is wall-clock capped
    // (ProcessRunner.wallClockLimit) and dies with everything in it
    // regardless, the same way the benchmark harness's own client.run()
    // task is never explicitly cancelled either.
    Task { await client.run() }
    return Repo(client: client)
}
