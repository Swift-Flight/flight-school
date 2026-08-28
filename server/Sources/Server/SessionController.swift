import FlightCore
import FlightWeb
import Foundation

/// The name PLAN §4's "anonymous id (cookie)" actually travels under.
///
/// Previously a plain `X-Session-Id` header: `Cookie`/`Set-Cookie` support
/// (`flight@8997a5a`) landed on `main` after the `v0.8.0` tag this package
/// resolved against at the time, so it wasn't reachable by a normal semver
/// pin. Fixed by cutting `flight` `v0.9.0` and bumping the pin — see
/// `CHANGELOG.md` there. A real cookie is strictly better here than the
/// header was: `HttpOnly` (on by default) keeps the value out of reach of
/// any injected script, whereas a header the client's own JS had to attach
/// by hand was necessarily readable by that same JS.
private let sessionCookieName = "fs_session"

struct WriteRequest: Decodable {
    let content: String
}

/// App tier: path → full file content, relative to the project root. A
/// separate route rather than an either-or body on `/write`, so each
/// route's `Decodable` stays unambiguous — the runner already knows which
/// shape to expect from the lease's tier, and the browser already knows
/// which kind of exercise it's on.
struct WriteFilesRequest: Decodable {
    let files: [String: String]
}

/// The execution module's HTTP surface (PLAN §4): mints or reuses an
/// anonymous session, forwards edits and run requests to whichever runner
/// that session is leased to. `/run` returns as soon as the runner call is
/// dispatched — the actual build/run output arrives over the
/// `session:<id>` channel the browser is expected to have already joined
/// (see SessionChannel), never in this response body. The session id
/// itself is also returned in `/api/session`'s JSON body (not just the
/// cookie) — the client needs it in hand to build that channel topic, and
/// an `HttpOnly` cookie is by design unreadable from the client's own JS.
@Controller
struct SessionController {
    // flight:hand-registered — registered in AppModule.configure(_:); it
    // composes an actor and two value types, so it isn't itself a scanned
    // @Component.
    @Autowired var sessionService: SessionService
    @ConfigValue("session.hardCapSeconds", default: 3600) var hardCapSeconds: Int

    /// `?tier=app` selects the app tier (PLAN §3); absent means `snippet`,
    /// so every existing caller is unchanged. A query parameter rather
    /// than a body for the same reason the runner's own `/lease` uses a
    /// header: this stays a POST with no body at all.
    ///
    /// The app tier's response also carries `previewPath` — where the
    /// browser's preview iframe should point. It's derived from the host
    /// of the runner this session actually landed on
    /// (`http://runner-1:9000` → `/preview/runner-1/`), matching the
    /// Caddyfile's per-runner routes. Deriving it here rather than letting
    /// the client guess means there's one numbering scheme, not two.
    @PostMapping("/api/session")
    func createSession(_ context: RequestContext) async -> Response {
        do {
            let requestedTier = context.request.queryParam("tier")
            guard let tier = requestedTier.map({ Tier(rawValue: $0) }) ?? .snippet else {
                return .problem(status: .badRequest, message: "unknown tier '\(requestedTier ?? "")'")
            }
            let sessionID = try await sessionService.getOrCreateSession(
                existingSessionID: context.request.cookie(sessionCookieName), tier: tier)
            var payload = [
                "sessionId": sessionID,
                "topic": SessionService.topic(for: sessionID),
            ]
            if tier == .app, let previewPath = await sessionService.previewPath(sessionID: sessionID) {
                payload["previewPath"] = previewPath
            }
            let response = try Response.json(payload)
            return response.settingCookie(
                Cookie(name: sessionCookieName, value: sessionID, maxAge: .seconds(hardCapSeconds)))
        } catch SessionBroker.BrokerError.poolExhausted {
            return .problem(status: .serviceUnavailable, message: "every runner is busy right now — try again shortly")
        } catch {
            return .problem(status: .badGateway, message: String(describing: error))
        }
    }

    @PostMapping("/api/session/write")
    func write(_ context: RequestContext, body: WriteRequest) async -> Response {
        guard let sessionID = context.request.cookie(sessionCookieName) else {
            return .problem(status: .badRequest, message: "no session — POST /api/session first")
        }
        do {
            try await sessionService.write(sessionID: sessionID, content: body.content)
            return .noContent
        } catch SessionBroker.BrokerError.unknownSession {
            return .problem(status: .notFound, message: "session expired or unknown")
        } catch {
            return .problem(status: .badGateway, message: String(describing: error))
        }
    }

    @PostMapping("/api/session/write-files")
    func writeFiles(_ context: RequestContext, body: WriteFilesRequest) async -> Response {
        guard let sessionID = context.request.cookie(sessionCookieName) else {
            return .problem(status: .badRequest, message: "no session — POST /api/session first")
        }
        do {
            try await sessionService.writeFiles(sessionID: sessionID, files: body.files)
            return .noContent
        } catch SessionBroker.BrokerError.unknownSession {
            return .problem(status: .notFound, message: "session expired or unknown")
        } catch {
            return .problem(status: .badGateway, message: String(describing: error))
        }
    }

    @PostMapping("/api/session/run")
    func run(_ context: RequestContext) async -> Response {
        guard let sessionID = context.request.cookie(sessionCookieName) else {
            return .problem(status: .badRequest, message: "no session — POST /api/session first")
        }
        do {
            try await sessionService.run(sessionID: sessionID)
            return .status(.accepted)
        } catch SessionBroker.BrokerError.unknownSession {
            return .problem(status: .notFound, message: "session expired or unknown")
        } catch {
            return .problem(status: .badGateway, message: String(describing: error))
        }
    }

    @PostMapping("/api/session/reset")
    func reset(_ context: RequestContext) async -> Response {
        guard let sessionID = context.request.cookie(sessionCookieName) else {
            return .problem(status: .badRequest, message: "no session — POST /api/session first")
        }
        do {
            try await sessionService.reset(sessionID: sessionID)
            return .noContent
        } catch SessionBroker.BrokerError.unknownSession {
            return .problem(status: .notFound, message: "session expired or unknown")
        } catch {
            return .problem(status: .badGateway, message: String(describing: error))
        }
    }
}
