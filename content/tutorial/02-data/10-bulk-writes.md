---
title: Bulk insert, update, delete
description: One statement across every matching row, with the count returned.
order: 10
---

Three operations, each one statement regardless of how many rows it
touches:

```swift
let stored = try await repo.insert(rows.map(Issue.init))
```

One round trip for however many rows — not one insert per element — and
it's atomic exactly as far as a single statement already is: every row
lands, or on any constraint violation, none do. Returned rows come back in
input order, so `stored[i]` still corresponds to `rows[i]`.

## Updating a query's worth of rows at once

```swift
let closed = try await repo.update(Issue.where { $0.status == "in_progress" }) {
    ($0.status.set(to: "closed"), $0.updatedAt.set(to: Date()))
}
```

Every matching row gets the same values — this is a "set this to that,
everywhere," not a per-row write, so a value that has to differ per row
still means fetching and writing rows one at a time. `.set(to:)` is typed
against its column, so assigning an `Int` to a `String` column is a compile
error the same way a mistyped `where` predicate would be. The return value
is a plain `Int`, the row count — zero is a completely normal answer, not
a sign anything went wrong.

## Deleting a query's worth of rows

```swift
let purged = try await repo.delete(Issue.where { $0.status == "closed" && $0.updatedAt < cutoff })
```

Same shape, same `Int` count back. The sharp edge worth knowing before you
reach for it: a query with no predicate at all deletes **every row in the
table**. `Issue.all` means all of them, and `repo.delete` honors that
rather than second-guessing it — there's no separate "are you sure"
mechanism standing between a missing `.where { }` and an empty table.

Both bulk `update` and `delete` reject a query carrying clauses a single
`UPDATE`/`DELETE` statement can't express — `LIMIT`, `OFFSET`, `ORDER BY`,
`GROUP BY`, `HAVING`, `DISTINCT` — rather than silently dropping them and
writing more rows than the query looked like it asked for.
