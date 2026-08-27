---
title: Path and query parameters
description: Typed extraction from the URL, before the handler body runs.
order: 3
---

```swift
@GetMapping("/posts/:id")
func show(_ context: RequestContext) -> String {
    guard let id = context.pathParam("id") else {
        return "missing id"  // in practice: see the next exercise on HTTPError
    }
    return "post \(id)"
}
```

`:id` in the route pattern names a path segment; `context.pathParam("id")`
reads it back. It's always a plain `String?` — Flight doesn't guess
whether `:id` means a `UUID`, an `Int`, or a slug, so converting it to the
type you actually want is your call, made explicitly:

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

This shape — extract as `String?`, convert, `guard`-else-throw — is the
one you'll write for every typed path parameter in every Flight app. It
looks like more code than a framework that guesses your type for you, and
it is: in exchange, "the id in the URL wasn't a UUID" and "no post has
that id" are two different, explicit, named failures instead of one
framework-generated 400 that doesn't say which.

## Query parameters

Same shape, different source:

```swift
@GetMapping("/posts")
func index(_ context: RequestContext) -> String {
    let onlyPublished = context.request.queryParam("published") == "true"
    return "published only: \(onlyPublished)"
}
```

```bash
curl "http://127.0.0.1:8080/posts?published=true"
```

`queryParam` reads from `context.request`, not `context` directly — path
parameters are properties of *this route's match*, query parameters are
properties of *the request itself*, and the API mirrors that distinction
rather than hiding it.
