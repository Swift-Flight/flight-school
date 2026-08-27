---
title: Your first route
description: "@Controller and @GetMapping, and why there is no route table to find."
order: 2
---

```swift
import FlightCore
import FlightWeb

@Controller
struct GreetingController {
    @GetMapping("/hello")
    func hello(_ context: RequestContext) -> String {
        "hello, flight"
    }
}
```

Add this file to `Sources/App/Controllers/`, rebuild, and:

```bash
curl http://127.0.0.1:8080/hello
# hello, flight
```

No registration call, no route table entry, nothing added to `AppModule`.
`@Controller` marks the type; `@GetMapping` marks the method; the
registration plugin (from the previous exercise) finds both at build time
and generates the wiring. If you're looking for "where do I add my new
route," the answer is: you don't, past writing the method.

## What a handler can return

A `String` becomes a `text/plain` body with a `200`. Most handlers return
something `Codable` instead, which becomes JSON:

```swift
struct Greeting: Codable {
    let message: String
}

@GetMapping("/hello-json")
func helloJSON(_ context: RequestContext) -> Greeting {
    Greeting(message: "hello, flight")
}
```

```bash
curl http://127.0.0.1:8080/hello-json
# {"message":"hello, flight"}
```

The response's `Content-Type` follows the return type — a `String` and a
`Codable` type don't need different handler shapes to get different
serialization, and you never construct a `Response` by hand unless you
need to (status codes and headers are next).

## `RequestContext`

Every handler method takes one as its first parameter (Flight resolves it
for you — it's never something you construct). It's your access point for
everything about the current request: path parameters, resolving
container components scoped to this request, and the logger. The next two
exercises are both about what you can pull out of it.
