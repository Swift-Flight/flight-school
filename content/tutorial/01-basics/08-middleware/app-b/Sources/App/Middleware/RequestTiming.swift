import FlightCore
import FlightWeb

@Middleware
struct RequestTiming {
    func handle(_ context: RequestContext, next: Next) async throws -> Response {
        let started = ContinuousClock.now
        let response = try await next(context)
        context.logger.info("\(response.status.code) in \(started.duration(to: .now))")
        return response
    }
}
