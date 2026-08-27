---
title: Bootstrap, modules, and the container
description: What flightRegisterAll actually wires, and in what order.
order: 1
---

Every Flight app boots the same four steps, in the same order, every time.
Once you've seen them once, you've seen every Flight app's startup:

```swift
@main
struct Main {
    static func main() async {
        do {
            try await Flight.bootstrap(
                configuration: try Configuration.load(),
                modules: [
                    FlightWebModule<FlightTransport>.self,
                    AppModule.self,
                    ActuatorModule.self,
                ])
        } catch {
            FileHandle.standardError.write(
                Data("App failed to start: \(String(reflecting: error))\n".utf8))
            exit(1)
        }
    }
}
```

1. **`Configuration.load()`** reads `flight.yaml` plus `FLIGHT_*`
   environment variables into one immutable value.
2. **The container is built.** Every listed module's `configure(_:)` runs,
   in dependency order — a module's `dependencies` form a DAG that's
   resolved once, not hoped for.
3. **The container freezes.** After this point, nothing can register a new
   component. A missing dependency is a startup failure here, not a
   runtime surprise three requests later.
4. **The server starts accepting connections.** Not before — there is no
   window where a request could arrive against a half-registered
   container.

## Your module

`AppModule` is the one file that says what your app is made of:

```swift
struct AppModule: FlightModule {
    static var dependencies: [any FlightModule.Type] { [] }

    func configure(_ container: Container) throws {
        try flightRegisterAll(container)
    }
}
```

`flightRegisterAll` is generated — not by you, and not at runtime. The
`FlightRegistrationPlugin` (named in `Package.swift`'s `plugins:` list)
scans your target at *build* time for every `@Component`, `@Controller`,
`@Service`, and `@Repository`, and writes the function that registers all
of them. Add a controller, and `flightRegisterAll` picks it up on the next
build — you never edit `AppModule` to wire in a new route.

## Why a DAG, not a list

`static var dependencies` matters the moment your app has more than one
module. If `AppModule` needs a database connection that some other module
provides, naming that module in `dependencies` guarantees it configures
first — regardless of the order modules are listed in `Main.swift`'s
array. You'll see this directly once Part 2 adds a database module ahead
of your own.

**Try it:** add a second `@Controller` to this project (any route you
like) and rebuild. Nothing in `AppModule` or `Main.swift` needs to change
for it to start serving — that's `flightRegisterAll` doing its job.
