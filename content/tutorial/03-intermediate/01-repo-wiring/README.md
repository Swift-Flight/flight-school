---
title: Wiring Hangar into Flight
description: Request-scoped repos, and the connection-affinity bug this guide exists to prevent.
order: 1
---

Every exercise so far constructed a `Repo` by hand. Inside a real Flight
app, a controller just asks for one:

```swift
@Controller
struct IssueController {
    @Autowired var repo: Repo

    @GetMapping("/issues/:id")
    func show(_ context: RequestContext) async throws -> Issue {
        guard let idText = context.pathParam("id"), let id = UUID(uuidString: idText) else {
            throw HTTPError(.badRequest, "malformed id")
        }
        guard let issue = try await repo.one(Issue.where { $0.id == id }) else {
            throw HTTPError(.notFound, "no such issue")
        }
        return issue
    }
}
```

This is the same `Issue` you queried directly in Part 2 — the entity and
the predicate haven't changed at all, only where the `Repo` comes from.

No connection pool in sight — `flight-data`'s Postgres module registers
`Repo` as a *scoped* component, resolved fresh per request, and every
`@Autowired var repo: Repo` in the same request resolves to the same
instance.

## Why "the same instance" is the whole point

The scoped `Repo` is bound to one connection leased for the life of the
request — not a pool it reaches into per query. That single decision is
what makes the rest of Flight's data story coherent: if two `Repo`
instances in one request could land on two different pooled connections,
a `@Transactional` method's uncommitted write would be invisible to a
Hangar query running in the same request, on the other connection, because
as far as Postgres is concerned they'd be two unrelated sessions. Binding
every repo in a request to the *same* connection is what makes
`@Transactional` and Hangar's own queries see each other's work.

## One transaction mechanism at a time

Both `@Transactional` and `repo.transaction { }` know how to open a
transaction on that shared connection — as a savepoint, if one is already
open — but neither coordinator can see the other's nesting. Pick one
per unit of work:

```swift
@Transactional                              // fine on its own
func transfer(amount: Decimal, from: UUID, to: UUID) async throws { ... }

func transfer(amount: Decimal, from: UUID, to: UUID) async throws {
    try await repo.transaction { tx in ... }   // also fine on its own
}
```

Interleaving them in the same call stack is the one thing to avoid — a
`repo.transaction { }` opened inside an already-`@Transactional` method
would emit its own literal `BEGIN`/`COMMIT` against a connection that
thinks it's still mid-transaction, and that `COMMIT` ends the enclosing
transaction early, making writes durable that the outer method meant to
still be able to roll back.
