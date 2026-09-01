---
title: Server-sent events
description: A one-way stream, for when a socket is more than the problem needs.
order: 4
---

```swift
@GetRoute("/events")
func events(_ context: RequestContext) -> Response {
    .serverSentEvents { events in
        events.send(data: "hello", event: "greeting")
    }
}
```

An SSE endpoint is an ordinary `@GetRoute` handler — no upgrade, no
separate protocol handshake, just a response whose body stays open.
`.serverSentEvents` sets `Content-Type: text/event-stream` and
`Cache-Control: no-cache` for you, and hands the closure a writer rather
than a raw byte stream: `events.send(data:event:id:)` encodes one
WHATWG-format event per call, escaping the value so a stray newline in
your data can't forge an extra field.

## Reacting to a client that leaves

`send` returns `false` once the client has disconnected — the natural way
to stop a loop that's producing from something else, like a subscription:

```swift
@GetRoute("/activity")
func activity(_ context: RequestContext) throws -> Response {
    let pubsub = try context.resolve((any PubSub).self)
    return .serverSentEvents { events in
        for await message in pubsub.subscribe("activity") {
            let line = String(decoding: message.payload, as: UTF8.self)
            guard events.send(data: line, event: "activity") else {
                return   // client went away; the subscription tears down with us
            }
        }
    }
}
```

Nothing here polls a cancellation flag — `guard ... else { return }` on the
writer's own return value is the whole disconnect check, and it composes
naturally with a `for await` loop over any async sequence, not just a
timer you control yourself.

## What an SSE handler doesn't hold

This connects directly to the connection-affinity lesson from the first
exercise of this part: `context.resolve(...)` above only checks out a
request-scoped component if something actually asks for one. An SSE
handler that never touches `Repo` never holds a database connection for
however long the stream stays open — a long-lived endpoint doesn't have to
mean a long-held connection out of the pool. That property doesn't come
free with every streaming design; it falls out of Flight's connections
being resolved on demand rather than reserved for the whole request up
front.

## Heartbeats

```swift
.serverSentEvents { events in
    while events.sendHeartbeat() {
        try? await Task.sleep(for: .seconds(15))
    }
}
```

A heartbeat is a comment line (`: keep-alive`), invisible to
`EventSource`'s `message`/named-event listeners on the client, and its
`Bool` return doubles as the same disconnect check as a real event — a
`while` loop over it stops itself the moment nobody's listening anymore.

SSE covers the one-directional case, which is usually what a dashboard or
an activity feed actually needs; a client that must also send messages
back over the same connection is what [WebSockets and
Channels](/tutorial/04-advanced/01-websockets) are for, later in this
tutorial.
