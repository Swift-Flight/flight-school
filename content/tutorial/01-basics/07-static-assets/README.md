---
title: Static assets and the asset pipeline
description: ETags, and serving a real frontend build alongside your API.
order: 7
---

A built frontend (an SPA's `dist/`, a prerendered site) mounts as a fallback,
not a route:

```swift
struct AppModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [] }

    func configure(_ container: Container) throws {
        try flightRegisterAll(container)

        container.pipeline("assets") { }
        container.assets(at: "/", root: "web/build", pipelines: ["assets"]) { options in
            options.spaFallback = "index.html"
            options.exclude = ["/api"]
            options.cache("no-cache", matching: "index.html")
            options.cache("public, max-age=31536000, immutable", matching: "_app/immutable/**")
        }
    }
}
```

The empty `pipeline("assets") { }` is the point of the lane, not a
placeholder: declaring a lane with nothing in it is how this traffic opts
out of everything the default lane carries. That needs flight `0.9.1` or
later — before it, an empty block registered nothing, the lane left no
trace, and the mount failed at startup complaining the lane was never
declared. (Found by compiling this exercise; see the changelog entry.)

"Fallback" is exact: a mount only answers a `GET`/`HEAD` the router didn't
match. A real route always wins, matched routes never pay anything for the
mount's existence, and `pipelines: ["assets"]` runs *only* an empty lane for
this traffic — no transaction binding, no authentication, nothing your API
routes' default lane carries that a request for `app.js` has no use for.
`exclude` carves `/api` back out even though this mount claims `/`, so a
miss under it reaches the ordinary 404 rather than the SPA shell.

## The shell fallback

`spaFallback` is what makes this a *frontend* mount and not just a file
server: a miss whose `Accept` prefers HTML gets `index.html` instead of a
404, which is what lets a client-side router handle `/dashboard/settings`
on a hard reload. A miss that doesn't prefer HTML — `fetch` sending
`Accept: application/json` — gets an honest 404 instead, so a typo'd API
call never comes back looking like a webpage.

## ETags and why two files get different treatment

Every served file gets a validator — either a fast weak tag from file
identity (the default: one `fstat`, already paid for) or, under
`options.etag = .contentHash`, a strong SHA-256 the client's `If-Range` can
trust for resuming a partial download. Either way, a request carrying
`If-None-Match` gets a bare `304 Not Modified` when the tag still matches —
no body, no re-transfer.

The two `cache(_:matching:)` rules above are doing the real work a static
frontend needs and a generic file server can't express by content type
alone: `_app/immutable/**` is named for its content hash by the bundler, so
it can be cached forever — a new deploy ships new filenames, never a stale
one under an old name. `index.html` is the opposite: same name, every
deploy, so it must always revalidate or a client would never see the new
build at all. Both are HTML-adjacent or JavaScript either way; the split
they need is about the *path*, which is exactly what these rules match on
rather than `Content-Type`.
