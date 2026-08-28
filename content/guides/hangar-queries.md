---
title: Queries
description: Predicates, joins, aggregates, and projections that decode into your own types.
order: 11
category: Hangar
---

A query is a value, composed from an entity's generated `Columns`:

```swift
let urgent = Issue.where { $0.status == "open" && $0.priority == "urgent" }
    .order { $0.updatedAt.desc() }
    .limit(20)
```

`debugSQL` shows exactly what it renders to — every column listed
explicitly (never `SELECT *`), every value a `$n` placeholder, never a
literal:

```
SELECT "id", "title", "status", "priority", "updated_at", "reporter_id" FROM "issues" WHERE (("status" = $1) AND ("priority" = $2)) ORDER BY "updated_at" DESC LIMIT 20
```

## Joins, aliases, and self-joins

```swift
Issue.join(Project.self, on: { issue, project in issue.projectID == project.id })
    .select(into: Row.self) { issue, project in
        (title: issue.title, project: project.name)
    }
```

`.leftJoin` is the same shape for "every row, matched or not." A self-join
needs an alias on at least one side — Hangar's two `FROM` entries must have
distinct names, or every column reference is ambiguous:

```swift
Employee.alias("manager").join(Employee.alias("report"),
    on: { manager, report in report.managerID == manager.id })
```

Forget the alias on a genuine self-join and it fails when the query
renders, naming the exact fix. A third table joins on from any two-table
join, its closure seeing all three column sets:

```swift
Issue.join(Project.self, on: { i, p in i.projectID == p.id })
    .join(User.self, on: { _, issue, user in issue.reporterID == user.id })
```

## Aggregates and projections

```swift
struct ProjectIssueCounts: Decodable { let projectID: UUID; let issueCount: Int }

try await repo.all(
    Issue.groupBy { $0.projectID }
        .having { $0.id.count() > 10 }
        .select(into: ProjectIssueCounts.self) { i in
            (i.projectID, i.id.count())
        })
```

`select(into:)` projects straight into any `Decodable` type — not just the
entity itself — for exactly the case a full model would over-fetch: an
aggregate, a narrow read, a join's combined row.

## Bulk writes

One statement, however many rows match:

```swift
let closed = try await repo.update(Issue.where { $0.status == "open" }) {
    ($0.status.set(to: "closed"), $0.updatedAt.set(to: Date()))
}
let purged = try await repo.delete(Session.where { $0.expiresAt < .now })
```

Both return an `Int` row count — zero is a normal answer, not an error. A
query with no predicate at all deletes every row in the table; Hangar
honors that rather than second-guessing it.

## Where to go next

- [Changesets](/guides/hangar-changesets) — validated, tracked single-row
  writes, the counterpart to the bulk writes above.
- [Associations & Preloading](/guides/hangar-preloading) — batched reads
  across related tables, without a join.
- [Transactions & Multi](/guides/hangar-transactions) — wrapping several
  writes into one unit of work.

[Part 2 of the tutorial](/tutorial/02-data) builds all of this as runnable
exercises, with `debugSQL` output shown for every query.
