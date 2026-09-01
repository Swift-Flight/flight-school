---
title: "flight-data: what Flight builds on top of Hangar"
description: Migrations, the DataSource/cache seam, and the Valkey drivers.
order: 11
---

Everything so far has been Hangar directly — a `Repo`, a `Configuration`,
a live connection, assembled by hand. A real Flight app instead wires a
whole store in at bootstrap, through `flight-data`:

```swift
container.register(dataSource: PostgresDataSource.self, name: PrimaryDataSource.name) { c in
    let settings = try DataSourceSettings.load(
        name: PrimaryDataSource.name, from: c.resolve(Configuration.self))
    return try PostgresDataSource(settings: settings)
}
```

`PostgresDataSource` is Hangar underneath — everything from `@Entity`
through bulk writes is the same API, reached through a pool Flight now owns
the lifecycle of. `register(dataSource:name:)` registers the pool as a
singleton, a request-scoped connection lease, and a liveness probe the
actuator can report on — all in one call, at the same `configure(_:)` step
every other module uses.

## Migrations

One Swift file per migration, discovered at *build* time by a compiler
plugin rather than a runtime directory scan — a malformed or duplicate
timestamp is a build error, never a deploy-time surprise:

```swift
struct CreateUsers: Migration {
    func up(_ schema: SchemaBuilder) {
        schema.createTable("users") { t in
            t.uuid("id").primaryKey().default(.raw("gen_random_uuid()"))
            t.text("email").notNull().unique()
            t.timestamptz("created_at").notNull().default(.now)
        }
    }

    func down(_ schema: SchemaBuilder) {
        schema.dropTable("users")
    }
}
```

Every migration runs in its own transaction together with its own
bookkeeping row, so a failure partway through leaves the schema exactly
where it started — never a half-applied table. Two properties worth
knowing before you rely on it: an already-applied migration is checksummed,
so editing one after the fact is a loud error, not a silent skip; and a
migration never runs at boot by default — it's a CLI command you invoke,
deliberately, not something that fires the first time a new binary starts.

## The cache seam

`@Cacheable` expands *into* the method it decorates rather than wrapping it
in a proxy — which is what makes it safe from the one footgun this pattern
usually carries: calling another `@Cacheable` method on `self` from inside
the same type still goes through the cache, because there is no proxy
object to have bypassed:

```swift
@Service
final class PricingService {
    @Autowired var repository: PriceRepository

    @Cacheable(namespace: "prices", ttl: .seconds(900))
    func price(for productID: ProductID, in region: Region) async throws -> Price {
        try await repository.computePrice(productID, region)
    }

    @CacheEvict(namespace: "prices", allEntries: true)
    func invalidateAll() async {}
}
```

## Swapping in Valkey

Both the data source and the cache are traits away from a distributed
backend, and switching is a module choice, never a code change:

```swift
.package(url: "https://github.com/Flight-Framework/flight-data.git",
         from: "0.3.0", traits: ["Postgres", "Valkey"])
```

```swift
modules: [
    FlightCacheValkeyModule.self,   // was FlightCacheModule.self
    // ...
]
```

`PricingService` above doesn't change at all — `@Cacheable` talks to
whichever cache the container resolves. The trait matters at the
`Package.swift` level for a different reason than convenience: a plain
`FlightCache` consumer that never asks for the `Valkey` trait never
resolves `valkey-swift` or `NIOSSL` at all, so an application that only
ever uses the in-memory cache pays nothing — not even at dependency
resolution — for a driver it never named.
