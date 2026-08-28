---
title: Testing
description: FlightWebTesting, FlightChannelsTesting, and three sizes of test.
order: 4
category: Flight
---

`TestClient` dispatches through the exact same `Request`/`Response`
values a real socket would produce — it skips the transport layer
entirely rather than routing through an in-process stand-in for it:

```swift
let container = try TestContainer.build(
    configuration: Configuration(values: ["app.name": "TestApp"])
) { AppModule() }
let client = try TestClient(container: container)
let response = await client.get("/")

#expect(response.status == .ok)
#expect(response.bodyText == "TestApp is flying")
```

Routing, middleware, dependency injection, and JSON encoding all run for
real. These tests are fast because the network is absent, not because
anything about the framework is stubbed.

## Three sizes

**Call the handler directly** — the smallest. No router involved at all:

```swift
let container = try TestContainer.build { FakeRepository(users: users) }
let controller = UserController(_flight: container)
let result = try await controller.list(.mock(container: container))
```

**`Components`** — the middle size, and the one most suites want:
register only the pieces a test actually exercises, then drive requests
through `TestClient` the way the example at the top does.

**`AppModule` plus an override** — the largest, and the only one that
checks the wiring itself:

```swift
let container = try TestContainer.build {
    AppModule()
} overriding: { container in
    container.override((any UserRepositoryProtocol).self, scope: .scoped) { _ in fakeUsers }
}
```

Freezing a container is where lifetime mistakes surface — a singleton
that captured a request-scoped dependency, or two modules claiming the
same key, are invisible to a test that never freezes one.

## What doesn't fit: Hangar directly

`FlightDataTesting` ships an `InMemoryDataSource` for the generic
`DataSource` seam, but it never executes SQL — it's a connection pool,
not a database. Hangar's `Repo` is built directly on `PostgresConnection`,
not on `DataSource`, so there's no seam to swap it into underneath a
`Repo`-based controller. The answer is the same principle the `Components`
size already teaches: depend on a protocol of your own, register a fake
conforming to it. A test that genuinely needs to prove a query renders
and runs correctly needs real Postgres — Hangar's own suite uses
`./scripts/test.sh` for exactly that, and an application should reach for
the same tier rather than a faster substitute pretending to be one.

## Testing channels without a socket

```swift
@Test("join rejected: flight:error with the rejection reason and the ref")
func joinRejected() async throws {
    let harness = try Harness()
    let wire = try await harness.wire()
    try wire.send(ref: "9", topic: "room:locked", event: "flight:join")

    let error = try await wire.nextEnvelope()
    #expect(error == Envelope(ref: "9", topic: "room:locked", event: "flight:error",
                               payload: ["reason": "forbidden"]))
}
```

`ChannelWireClient` is a deliberately dumb protocol driver — raw
`Envelope`s over an in-memory socket, no heartbeats, no reconnect, no
correlation of its own — for asserting on the wire itself. When the
assertion is instead about how a real client built on `ChannelClient`
behaves, `InMemoryChannelTransport` drives one against a real server with
the same zero sockets, reconnection included. Both sit on the identical
`InMemoryWebSocket` primitive `TestClient.webSocket(_:)` already uses —
Channels testing is built on Web's, not a separate mechanism.

## Where to go next

- [Channels](/guides/channels) — the protocol `ChannelWireClient` asserts
  on.
- [Routing and Controllers](/guides/routing-and-controllers) — what
  `TestClient` actually dispatches through.

[Part 3](/tutorial/03-intermediate/07-testing) and
[Part 4](/tutorial/04-advanced/06-testing-channels) of the tutorial build
both halves of this as runnable exercises.
