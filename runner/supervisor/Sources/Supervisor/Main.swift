import FlightCore
import FlightTransport
import FlightWeb
import Foundation

struct AppModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [] }

    func configure(_ container: Container) throws {
        // WorkspaceState is a plain actor, not a @Component — registered
        // by hand rather than risking an unverified assumption about
        // whether the @Component macro supports actor types.
        container.register(WorkspaceState.self, scope: .singleton) { _ in
            WorkspaceState()
        }
        try flightRegisterAll(container)
    }
}

@main
struct Main {
    static func main() async {
        do {
            let configuration = try Configuration.load()
            let workspacePath = try configuration.getIfPresent("workspace.live", as: String.self) ?? "/workspace"

            // The `.build` baked into this image at build time is not
            // actually usable as-is: verified directly that the first
            // `swift build` inside a freshly started container from this
            // image recompiles everything from scratch (896 tasks, ~60s)
            // rather than the ~2s incremental rebuild a single changed
            // file should cost — almost certainly Docker's layer
            // export/import normalizing file timestamps in a way that
            // breaks SwiftPM's staleness detection across that boundary.
            // A *second* build, live within the same running container,
            // is correctly fast — so the fix is paying this cost once,
            // here, before the container starts accepting leases, rather
            // than making an unlucky learner's first session pay it.
            // One warm workspace per tier (PLAN §4's "prebuilt workspaces,
            // one per execution tier/template") — the pool stays
            // undifferentiated, so every runner must be ready to serve
            // either tier. Sequential rather than concurrent: the
            // container is capped at 2 CPUs, so two `swift build`s would
            // mostly contend rather than overlap.
            for tier in [Tier.snippet, Tier.app] {
                try warmUp(
                    workspace: URL(fileURLWithPath: workspacePath).appending(path: tier.rawValue))
            }

            try await Flight.bootstrap(
                configuration: configuration,
                modules: [
                    FlightWebModule<FlightTransport>.self,
                    AppModule.self,
                ])
        } catch {
            FileHandle.standardError.write(
                Data("supervisor failed to start: \(String(reflecting: error))\n".utf8))
            exit(1)
        }
    }

    private static func warmUp(workspace: URL) throws {
        FileHandle.standardError.write(Data("warming up workspace at \(workspace.path)...\n".utf8))
        let started = ContinuousClock.now

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build"]
        process.currentDirectoryURL = workspace
        // Inherits stdout/stderr directly — this is startup, before any
        // session or SSE stream exists to forward it to.

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WarmUpError.buildFailed(exitCode: process.terminationStatus)
        }
        FileHandle.standardError.write(
            Data("workspace warm after \(started.duration(to: .now))\n".utf8))
    }

    enum WarmUpError: Error, CustomStringConvertible {
        case buildFailed(exitCode: Int32)
        var description: String {
            switch self {
            case .buildFailed(let code):
                return "workspace warm-up build failed (exit \(code)) — refusing to start"
            }
        }
    }
}
