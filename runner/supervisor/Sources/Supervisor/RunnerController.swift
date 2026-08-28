import FlightCore
import FlightWeb
import Foundation
import HTTPTypes

extension HTTPField.Name {
    /// The lease id every call after `/lease` must present — a fixed,
    /// known-valid literal, so the force-unwrap here can never fail.
    static let leaseID = HTTPField.Name("X-Lease-Id")!
    /// This session's own Postgres connection string (PLAN §3's `db`
    /// tier), set once at `/lease` time — absent entirely for a
    /// `snippet`-tier session. A header, not a JSON body, so `/lease`
    /// keeps working with no body at all for the common no-database case,
    /// and so the connection string (which may itself contain characters
    /// a JSON-body macro's Decodable binding would need to escape) never
    /// needs any encoding beyond what an HTTP header value already allows.
    static let databaseURL = HTTPField.Name("X-Database-Url")!
    /// Which execution tier this lease wants (`snippet`/`app`). Absent
    /// means `snippet`, so every pre-M3 caller keeps working untouched.
    /// A header for the same reason `X-Database-Url` is one: `/lease`
    /// stays a request with no body at all.
    static let tier = HTTPField.Name("X-Tier")!
}

/// The snippet tier writes one file and names it nowhere (there is only
/// one it's allowed to touch); the app tier writes a set, keyed by path
/// relative to the workspace root. Exactly one of the two is expected per
/// request, decided by the lease's tier — a mismatch is rejected rather
/// than silently half-applied.
struct WriteRequest: Decodable {
    let content: String?
    let files: [String: String]?
}

/// The runner's internal control API (PLAN §4): one workspace, leased to
/// at most one session at a time. Every route but `/lease` requires the
/// lease id it returned, checked against `state` — a stale id from a
/// previous session, or a guess, is rejected, never just "present."
@Controller
struct RunnerController {
    // flight:hand-registered — registered in AppModule.configure(_:),
    // since it's a plain actor, never scanned as a @Component.
    @Autowired var state: WorkspaceState
    @ConfigValue("workspace.live", default: "/workspace") var liveWorkspacePath: String
    @ConfigValue("workspace.pristine", default: "/workspace-pristine") var pristineWorkspacePath: String

    /// Both paths are now *roots* holding one subdirectory per tier
    /// (`/workspace/snippet`, `/workspace/app`) rather than being a single
    /// workspace themselves — one image carries a warm build per tier.
    private func liveWorkspace(_ tier: Tier) -> URL {
        URL(fileURLWithPath: liveWorkspacePath).appending(path: tier.rawValue)
    }

    private func pristineWorkspace(_ tier: Tier) -> URL {
        URL(fileURLWithPath: pristineWorkspacePath).appending(path: tier.rawValue)
    }

    /// The one file a snippet-tier session is ever allowed to change.
    private func exerciseFile(_ tier: Tier) -> URL {
        liveWorkspace(tier).appending(path: "Sources/exercise/main.swift")
    }

    /// The subtrees an app-tier session may write into, and the only ones
    /// `/reset` restores.
    ///
    /// This is the tier's one real security boundary, and it is structural
    /// rather than per-exercise: `Package.swift` is itself Swift that
    /// `swift build` *evaluates*, so a write reaching it is arbitrary code
    /// execution by a shorter path than the one this product already
    /// deliberately offers (PLAN §5) — outside the sandbox's own limits
    /// rather than inside them. `flight.yaml` is excluded for a smaller
    /// reason: it carries the host/port binding the preview proxy depends
    /// on. An exercise's own "editable files" list is a content concern
    /// layered above this, not a second gate here.
    private static let appEditableRoots = ["Sources/App", "Tests/AppTests"]

    private static let maxContentBytes = 32 * 1024
    /// A whole app-tier write, across every file in it.
    private static let maxRequestBytes = 256 * 1024

    @PostMapping("/lease")
    func lease(_ context: RequestContext) async -> Response {
        let requested = context.request.headers[.tier]
        guard let tier = requested.map({ Tier(rawValue: $0) }) ?? .snippet else {
            return .problem(status: .badRequest, message: "unknown tier '\(requested ?? "")'")
        }
        guard
            let id = await state.lease(
                tier: tier, databaseURL: context.request.headers[.databaseURL])
        else {
            return .problem(status: .conflict, message: "already leased")
        }
        return (try? Response.json(["leaseId": id], status: .created)) ?? .status(.internalServerError)
    }

    @PostMapping("/write")
    func write(_ context: RequestContext, body: WriteRequest) async throws -> Response {
        guard await isLeaseValid(context) else {
            return .problem(status: .forbidden, message: "no valid lease")
        }
        let tier = await state.tier
        switch tier {
        case .snippet:
            guard let content = body.content else {
                return .problem(status: .badRequest, message: "snippet-tier write needs `content`")
            }
            guard content.utf8.count <= Self.maxContentBytes else {
                return .problem(
                    status: .contentTooLarge, message: "content exceeds \(Self.maxContentBytes) bytes")
            }
            try Data(content.utf8).write(to: exerciseFile(tier), options: .atomic)
        case .app:
            guard let files = body.files else {
                return .problem(status: .badRequest, message: "app-tier write needs `files`")
            }
            let total = files.values.reduce(0) { $0 + $1.utf8.count }
            guard total <= Self.maxRequestBytes else {
                return .problem(
                    status: .contentTooLarge, message: "write exceeds \(Self.maxRequestBytes) bytes")
            }
            let root = liveWorkspace(tier)
            // Resolve and validate *every* path before writing *any* — a
            // partially-applied write would leave the workspace in a state
            // neither the learner nor `/reset` expects.
            var resolved: [(URL, String)] = []
            for (path, content) in files {
                guard content.utf8.count <= Self.maxContentBytes else {
                    return .problem(
                        status: .contentTooLarge,
                        message: "\(path) exceeds \(Self.maxContentBytes) bytes")
                }
                guard let target = Self.resolveEditablePath(path, under: root) else {
                    return .problem(
                        status: .badRequest,
                        message: "\(path) is not an editable file — writes must be under "
                            + Self.appEditableRoots.joined(separator: " or "))
                }
                resolved.append((target, content))
            }
            for (target, content) in resolved {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(content.utf8).write(to: target, options: .atomic)
            }
        }
        return .noContent
    }

    @PostMapping("/run")
    func run(_ context: RequestContext) async -> Response {
        guard await isLeaseValid(context) else {
            return .problem(status: .forbidden, message: "no valid lease")
        }
        let tier = await state.tier
        let workspace = liveWorkspace(tier)
        let databaseURL = await state.databaseURL
        let state = state
        return .serverSentEvents { events in
            let stream =
                switch tier {
                case .snippet: ProcessRunner.run(in: workspace, databaseURL: databaseURL)
                case .app:
                    ProcessRunner.runApp(in: workspace, databaseURL: databaseURL, state: state)
                }
            for await event in stream {
                guard events.send(data: Self.encode(event), event: Self.name(event)) else { return }
            }
        }
    }

    @PostMapping("/reset")
    func reset(_ context: RequestContext) async throws -> Response {
        guard await isLeaseValid(context) else {
            return .problem(status: .forbidden, message: "no valid lease")
        }
        let tier = await state.tier
        await state.killRunning()
        try restorePristine(tier)
        return .noContent
    }

    @PostMapping("/release")
    func release(_ context: RequestContext) async throws -> Response {
        guard await isLeaseValid(context) else {
            return .problem(status: .forbidden, message: "no valid lease")
        }
        // Read before `release()`, which clears the tier along with the
        // lease — restoring the wrong tier's workspace would leave the
        // next session's editable files untouched from the last one's.
        let tier = await state.tier
        await state.release()
        try restorePristine(tier)
        return .noContent
    }

    private func isLeaseValid(_ context: RequestContext) async -> Bool {
        guard let candidate = context.request.headers[.leaseID] else { return false }
        return await state.isValid(candidate)
    }

    /// The write allowlist, as a resolution: `nil` means "refuse."
    ///
    /// Rejects absolute paths and any `..` component *before* resolving
    /// rather than relying on normalization to undo them afterward — the
    /// check that matters is on what was asked for, not on what a
    /// path-cleaning routine happened to turn it into. What survives is
    /// then required to sit under one of the editable roots.
    static func resolveEditablePath(_ path: String, under root: URL) -> URL? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), !components.isEmpty,
            !components.contains(".."), !components.contains("."),
            !components.contains("")
        else { return nil }
        let normalized = components.joined(separator: "/")
        guard appEditableRoots.contains(where: { normalized.hasPrefix($0 + "/") }) else {
            return nil
        }
        return root.appending(path: normalized)
    }

    /// Puts the editable surface back to the template's own state.
    ///
    /// For the app tier this is deliberately scoped to the same subtrees
    /// the write allowlist governs, rather than replacing the whole
    /// workspace: `.build` lives at the project root, so wiping the
    /// workspace wholesale would throw away the warm build this tier
    /// exists to keep, turning the next run into a cold one. Removing and
    /// recopying just those subtrees also handles a learner's *added*
    /// files, which a file-by-file overwrite would leave behind.
    private func restorePristine(_ tier: Tier) throws {
        switch tier {
        case .snippet:
            let source = pristineWorkspace(tier).appending(path: "Sources/exercise/main.swift")
            let data = try Data(contentsOf: source)
            try data.write(to: exerciseFile(tier), options: .atomic)
        case .app:
            let live = liveWorkspace(tier)
            let pristine = pristineWorkspace(tier)
            for relative in Self.appEditableRoots {
                let target = live.appending(path: relative)
                let source = pristine.appending(path: relative)
                if FileManager.default.fileExists(atPath: target.path()) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
            }
        }
    }

    private static func name(_ event: RunEvent) -> String {
        switch event {
        case .buildOutput: return "build_output"
        case .buildDone: return "build_done"
        case .runOutput: return "run_output"
        case .exited: return "exited"
        case .timedOut: return "timed_out"
        case .truncated: return "truncated"
        case .serverStarted: return "server_started"
        }
    }

    private static func encode(_ event: RunEvent) -> String {
        switch event {
        case .buildOutput(let line), .runOutput(let line):
            return line
        case .buildDone(let code), .exited(let code):
            return "\(code)"
        case .timedOut, .truncated, .serverStarted:
            return ""
        }
    }
}
