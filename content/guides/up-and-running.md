---
title: Up and Running
description: From an empty directory to a running Flight app in one page.
order: 0
category: Flight
---

```bash
flight new MyService
cd MyService
swift run
```

`flight new` generates a complete, buildable project from one of three
tiers — `skeleton` (the smallest thing that runs), `basics`, or `demo` —
defaulting to `skeleton`. The alternative most frameworks choose is one
starting template with everything wired in, disabled by config flags.
Flight's tiers are a different bet: what you didn't ask for was never
resolved, so it can never be a build you have to explain. A `skeleton`
project's `Package.swift` has exactly one dependency line naming exactly
one trait — that line is the whole story of what the project depends on.

## What you get

```
MyService/
  Package.swift
  flight.yaml
  Sources/App/
    Main.swift
    Controllers/HealthController.swift
    Entities/      (empty)
    Repos/         (empty)
  Tests/AppTests/HealthControllerTests.swift
```

`Main.swift` is the whole boot sequence, in one place: configuration
loads, the container is built (every module's `dependencies` forming a
DAG resolved once), the container freezes, and only then does the server
start accepting requests. There's no window where a request could arrive
against a half-registered container.

`HealthController` is the one route worth curling once `swift run` is up:

```swift
@Controller
struct HealthController {
    @ConfigValue("app.name") var appName: String

    @GetMapping("/")
    func index(_ context: RequestContext) -> String {
        "\(appName) is flying"
    }
}
```

```bash
curl http://127.0.0.1:8080/
# App is flying
```

Two macros doing real work: `@Controller` is what the build-time
registration plugin looks for — no separate step registers this route
anywhere. `@ConfigValue("app.name")` reads `flight.yaml`'s `app.name` key,
and because there's no `default:` argument, a misspelled key is a
*build* failure, not a runtime surprise.

## Tests, from the same command

```bash
swift test
```

The generated test drives the same route through `TestClient` — routing,
middleware, and dependency injection all run for real, with no socket and
no port to collide with:

```swift
@Test("the index route answers with the configured application name")
func index() async throws {
    let container = try TestContainer.build(
        configuration: Configuration(values: ["app.name": "TestApp"])
    ) { AppModule() }
    let client = try TestClient(container: container)
    let response = await client.get("/")
    #expect(response.bodyText == "TestApp is flying")
}
```

## Where to go next

- [Routing and Controllers](/guides/routing-and-controllers) — the next
  thing worth adding to `HealthController`'s file.
- [Configuration](/guides/configuration) — the three layers `app.name`
  above actually comes from.
- [Testing](/guides/testing) — what `TestClient` is doing under the hood,
  and the other two sizes of test beyond the one above.

[Part 0 of the tutorial](/tutorial/00-setup) walks through all of this
one exercise at a time, including what each generated file is for.
