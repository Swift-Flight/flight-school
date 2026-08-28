import FlightCore
import FlightWeb
import Foundation
import HTTPTypes

extension HTTPField.Name {
    /// The session id every call after `/api/session` must present.
    ///
    /// PLAN §4 says "anonymous id (cookie)," but `Cookie`/`Set-Cookie`
    /// support (`flight@8997a5a`, "Add cookie support") landed on `main`
    /// *after* the `v0.8.0` tag this package actually resolves against —
    /// checked directly (`git log v0.8.0..HEAD`), not assumed — so it isn't
    /// reachable by a normal semver pin yet. A plain request header carries
    /// the same session id with the same security shape: per
    /// `SessionService`'s doc comment, knowing the id already *is* the
    /// credential (v1 has no accounts, PLAN §1), so a cookie's extra
    /// browser-managed persistence and HttpOnly framing don't change what's
    /// actually being trusted, only where the browser stores it. Revisit
    /// once flight cuts a release past `v0.8.0`.
    static let sessionID = HTTPField.Name("X-Session-Id")!
}

struct WriteRequest: Decodable {
    let content: String
}

/// The execution module's HTTP surface (PLAN §4): mints or reuses an
/// anonymous session, forwards edits and run requests to whichever runner
/// that session is leased to. `/run` returns as soon as the runner call is
/// dispatched — the actual build/run output arrives over the
/// `session:<id>` channel the browser is expected to have already joined
/// (see SessionChannel), never in this response body.
@Controller
struct SessionController {
    // flight:hand-registered — registered in AppModule.configure(_:); it
    // composes an actor and two value types, so it isn't itself a scanned
    // @Component.
    @Autowired var sessionService: SessionService

    @PostMapping("/api/session")
    func createSession(_ context: RequestContext) async -> Response {
        do {
            let sessionID = try await sessionService.getOrCreateSession(
                existingSessionID: context.request.headers[.sessionID])
            return try Response.json([
                "sessionId": sessionID,
                "topic": SessionService.topic(for: sessionID),
            ])
        } catch SessionBroker.BrokerError.poolExhausted {
            return .problem(status: .serviceUnavailable, message: "every runner is busy right now — try again shortly")
        } catch {
            return .problem(status: .badGateway, message: String(describing: error))
        }
    }

    @PostMapping("/api/session/write")
    func write(_ context: RequestContext, body: WriteRequest) async -> Response {
        guard let sessionID = context.request.headers[.sessionID] else {
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

    @PostMapping("/api/session/run")
    func run(_ context: RequestContext) async -> Response {
        guard let sessionID = context.request.headers[.sessionID] else {
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
        guard let sessionID = context.request.headers[.sessionID] else {
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
