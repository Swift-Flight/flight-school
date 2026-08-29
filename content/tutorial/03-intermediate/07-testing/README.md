---
title: Testing
description: Three sizes of test, and the in-memory transport that makes the smallest one fast.
order: 7
---

Every test so far in this tutorial would already have used `TestClient` if
it had been shown running:

```swift
@Test("the index route answers with the configured application name")
func index() async throws {
    let container = try TestContainer.build(
        configuration: Configuration(values: ["app.name": "TestApp"])
    ) { AppModule() }
    let client = try TestClient(container: container)
    let response = await client.get("/")
    #expect(response.status == .ok)
    #expect(response.bodyText == "TestApp is flying")
}
```

`TestClient` doesn't route through an in-process stand-in for the network
— it skips the transport layer entirely, dispatching straight through the
same `Request`/`Response` values a real socket would eventually produce.
Routing, middleware, dependency injection, and JSON encoding all run for
real. These tests are fast because the network is absent, not because
anything about the framework is stubbed.

## Three sizes, not two

"Fast" and "thorough" usually trade off against each other one axis at a
time: how much of the container gets built.

**Call the handler directly** — the smallest. Construct the controller
yourself and call the method; no router involved at all:

```swift
let container = try TestContainer.build { FakeRepository(users: users) }
let controller = UserController(_flight: container)
let result = try await controller.list(.mock(container: container))
```

Reach for this when the logic under test is the point and routing isn't —
`RequestContext.mock(container:)` builds a context with no real request
behind it at all.

**`Components`** — the middle size, and the one most suites want. Register
only the pieces a test actually exercises, then drive requests through
`TestClient` the way the example at the top of this page does. This is
"the real controller, routing, middleware, DI" without booting anything
the test doesn't touch.

**`AppModule` plus an override** — the largest, and the only one that
checks the wiring itself:

```swift
let container = try TestContainer.build {
    AppModule()
} overriding: { container in
    container.override((any UserRepositoryProtocol).self, scope: .scoped) { _ in fakeUsers }
}
```

Freezing a container is where lifetime mistakes surface — a singleton that
accidentally captured a request-scoped dependency, or two modules both
claiming the same key, are invisible to a test that never freezes one.
This size boots every module the real application boots and swaps exactly
one seam, so it's the one test that would actually catch that class of
bug.

## What doesn't fit this story: Hangar directly

`FlightDataTesting` ships an `InMemoryDataSource` for testing against the
generic `DataSource` seam — but it's a connection pool, not a database: it
never executes SQL, only records that something was asked of it. That's
enough for testing your own scope-bound-connection wiring, but Hangar's
`Repo` is built directly on `PostgresConnection`, not on the generic
`DataSource` protocol, so there's no seam here to swap `InMemoryDataSource`
into underneath it.

The answer isn't a faster fake for `Repo` — it's the same principle the
`Components` size already teaches: depend on a protocol, and register a
fake conforming to it, exactly like `FakeRepository` above. A test that
genuinely needs to prove a *query* renders and runs correctly needs real
Postgres, the same way Hangar's own test suite does — `./scripts/test.sh`,
starting a throwaway server and tearing it down, is the honest tier for
that, not a faster substitute pretending to be one.
