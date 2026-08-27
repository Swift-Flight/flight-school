---
title: Middleware and pipeline lanes
description: Ordering cross-cutting concerns explicitly, not by registration accident.
order: 8
---

A middleware layer is a type, not a closure, and it decides whether the
request continues by calling — or not calling — the rest of the chain:

```swift
@Middleware
struct RequestTiming {
    func handle(_ context: RequestContext, next: Next) async throws -> Response {
        let started = ContinuousClock.now
        let response = try await next(context)
        context.logger.info("\(response.status.code) in \(started.duration(to: .now))")
        return response
    }
}
```

`@Middleware` registers `RequestTiming` as an ordinary singleton component —
`@Autowired` can resolve it, a test can construct it directly — exactly like
`@Component`. What it deliberately does *not* do is enroll the type in any
pipeline. That's a separate, explicit step:

```swift
container.pipeline {
    RequestTiming.self
}
```

A `@Middleware` type written but left out of every `pipeline { }` block
simply never runs, which is a one-line fix to notice and make, not a
silently wrong answer shipping because a registration call was forgotten
somewhere.

## Calling `next` is the whole contract

`Next` is `@Sendable (RequestContext) async throws -> Response` — a plain
value in, a value out. A layer that wants to short-circuit just doesn't call
it:

```swift
@Middleware
struct MaintenanceGate {
    @ConfigValue("app.maintenanceMode", default: false) var maintenanceMode: Bool

    func handle(_ context: RequestContext, next: Next) async throws -> Response {
        guard !maintenanceMode else {
            throw HTTPError(.serviceUnavailable, "down for maintenance")
        }
        return try await next(context)
    }
}
```

No `MiddlewareResult` enum, no closure-arity to get right — a layer that has
nothing to add to a failure just lets a thrown error propagate outward
through every enclosing layer exactly like an ordinary Swift call. Listing
both types orders them, outermost first:

```swift
container.pipeline {
    RequestTiming.self
    MaintenanceGate.self
}
```

`RequestTiming` wraps `MaintenanceGate` wraps the handler — a request the
gate turns away is still timed, because timing sits outside it. Reverse the
two lines and it wouldn't be.

## Named lanes

The pipeline above extends the *default* lane every route runs unless told
otherwise. A controller that wants a different stack entirely — nothing at
all, or something narrower — names its own:

```swift
container.pipeline("admin") {
    RequestTiming.self
    MaintenanceGate.self
}

@Controller("/admin", pipelines: ["admin"])
struct AdminController { /* ... */ }
```

This is the same mechanism the previous exercise's asset mount used —
`pipelines: ["assets"]` names a lane too, just one declared empty. Naming an
undeclared lane fails at bootstrap, pointing at the route and the lane —
never a 500 discovered from a request three deploys later.
