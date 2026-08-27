---
title: Responses, status codes, and HTTPError
description: Shaping what a handler sends back, and how it fails on purpose.
order: 5
---

Returning a plain `String` or `Codable` value (§2) covers the common case,
but a handler that needs to choose its own status code or add a header
constructs a `Response` directly:

```swift
@PostMapping("/posts")
func create(_ context: RequestContext, body: CreatePost) throws -> Response {
    try Response.json(["id": newID.uuidString], status: .created)
}

@DeleteMapping("/posts/:id")
func delete(_ context: RequestContext) -> Response {
    .noContent
}
```

`Response.json` is the same JSON encoding a `Codable` return value gets
implicitly — this is that path, called by hand so you can pass `status:`.
`Response.text(_:status:)` and `Response.html(_:status:)` are the same idea
for the other two body shapes you'll reach for by hand. All three exist
because "the usual encoding, an unusual status code" shouldn't require
building headers and a body yourself.

## Failing on purpose

A handler doesn't need to catch its own errors to answer with the right
status code — it throws, and names the status when it does:

```swift
@GetMapping("/posts/:id")
func show(_ context: RequestContext) async throws -> Post {
    guard let idText = context.pathParam("id"), let id = UUID(uuidString: idText) else {
        throw HTTPError(.badRequest, "malformed id")
    }
    guard let post = try await repo.one(Post.where { $0.id == id }) else {
        throw HTTPError(.notFound, "no such post")
    }
    return post
}
```

Both throws are the whole error path — nothing downstream needs a `catch`.
Every `HTTPError` (and anything else conforming to `HTTPErrorRepresentable`,
which is how `BodyDecodingError`'s 400 and the previous exercise's 415 reach
the wire) is caught centrally and rendered as
[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) `application/problem+json`:

```bash
curl -i http://127.0.0.1:8080/posts/not-a-uuid
```
```
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json

{"status":400,"title":"Bad Request","detail":"malformed id"}
```

`title` is always the status's own reason phrase; `detail` is the message
you passed. Omit the message — `throw HTTPError(.forbidden)` — and `detail`
disappears from the body entirely rather than repeating `title` back at you.

## What never reaches the client

An error that doesn't conform to `HTTPErrorRepresentable` — a database
timeout, a force-unwrap you didn't mean to ship, anything unplanned —
answers a bare `500` with `detail` omitted:

```json
{"status":500,"title":"Internal Server Error"}
```

The actual error, in full, goes to `context.logger` — never to the response
body. This isn't a try/catch you write per handler; it's the same central
mapping that renders `HTTPError`, falling through to its `default` case.
The practical effect: a handler can let an unexpected error simply propagate
and trust that whatever it was, the client learns nothing more than "the
server failed" while you learn everything, in the logs.
