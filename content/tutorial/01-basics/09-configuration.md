---
title: Configuration
description: flight.yaml, environment variables, and @Settings.
order: 9
---

Bootstrap's first step (§1) was `Configuration.load()`, resolving three
layers into one immutable value — frozen before the container is even
built, so nothing downstream can read a config value that changes mid-run:

1. **`flight.yaml`** — defaults shared by every environment.
2. **`flight-{env}.yaml`** — an overlay for one environment, selected by
   `FLIGHT_ENV` (`dev` if unset; `test`, `staging`, and `prod` are built in,
   and an app can define more). `FLIGHT_ENV=staging` loads
   `flight-staging.yaml` on top of the base file.
3. **`FLIGHT_*` environment variables** — always win over both files.

## One value: `@ConfigValue`

The anatomy exercise (§3) used the required form —
`@ConfigValue("app.name")`, a build error if `app.name` is missing from
`flight.yaml`. A key that's genuinely optional gets a default instead:

```swift
@ConfigValue("app.maintenanceMode", default: false) var maintenanceMode: Bool
```

— which is exactly the property the middleware exercise's `MaintenanceGate`
declared, without naming it yet. Absent from every layer, it's `false`;
present but the wrong shape (a string where a `Bool` was expected) still
fails at bootstrap rather than silently keeping the default.

## A related group: `@Settings`

Several keys that belong together bind once as a typed struct instead of
one `@ConfigValue` per field:

```swift
@Settings("posts")
struct PostsSettings {
    var pageSize: Int = 25
    var maxPageSize: Int = 100
}
```

```yaml
posts:
  page-size: 25
  max-page-size: 100
```

`pageSize` binds `posts.page-size` — every property name is transformed
`camelCase` → `kebab-case` to build its key, matching `flight.yaml`'s own
convention. Resolve it exactly like any other component:

```swift
@Controller
struct PostController {
    @Autowired var settings: PostsSettings

    @GetMapping("/posts")
    func index(_ context: RequestContext) -> String {
        "page size: \(settings.pageSize)"
    }
}
```

A property with no default (no `= value`) is required, checked against
`flight.yaml`'s base layer at compile time — the same "build error, not a
bootstrap surprise" guarantee `@ConfigValue`'s no-default form makes.

## The environment-variable name a key actually reads

The transform is fixed and one-way: uppercase, `.` → `_`, prefixed
`FLIGHT_`. `app.name` reads `FLIGHT_APP_NAME`; `posts.max-page-size` reads
`FLIGHT_POSTS_MAX-PAGE-SIZE` — note the literal dash. Only dots are
rewritten, so a `@Settings`-derived key with more than one word in its
property name keeps its dash straight through into the variable name, and a
dash is not legal in a variable name most shells can `export`. It's a real
gap, not a rare one: `pageSize`, `signingKey`, `tokenLifetime` all produce
one. For a key shaped like that, reach for the `flight-{env}.yaml` overlay
instead of an environment variable — `FLIGHT_ENV` itself has no such
problem, being a single word.
