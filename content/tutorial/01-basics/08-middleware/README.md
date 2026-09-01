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
        let elapsed = started.duration(to: .now)
        context.logger.info("\(response.status.code) in \(elapsed)")
        return response.settingHeader(HTTPField.Name("X-Response-Time")!, "\(elapsed)")
    }
}
```

It both logs the timing and returns it as a header, so you can see the
layer working with `curl -i` as well as in the log.

`@Middleware` registers `RequestTiming` as an ordinary singleton component —
`@Inject` can resolve it, a test can construct it directly — exactly like
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

**This is why the exercise touches two files**: `RequestTiming.swift`,
where the type goes, and `Main.swift`, where it gets enrolled. Write only
the first and rebuild — the app serves exactly as before and the header
never appears, because nothing put the layer in a pipeline. Add the
`pipeline { }` block to `AppModule.configure`, rebuild, and it does:

```
HTTP/1.1 200 OK
X-Response-Time: 0.000118622 seconds
```

Now ask for a route that doesn't exist:

```
HTTP/1.1 404 Not Found
X-Response-Time: 4.667e-05 seconds
```

That second one is the point. The layer wraps *dispatch*, not your
handlers, so a request that matched no route is timed too — there was no
handler involved for it to have wrapped.

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
