---
title: Preloading and the N+1 story
description: The measured 5× — batched queries instead of one-per-parent.
order: 6
---

```swift
let issues = try await repo.all(
    Issue.where { $0.status == "open" }
        .preload(\.reporter)
        .preload(\.assignee))
```

Two associations, two extra queries total — never one per issue. Each
`.preload` runs its own batched query keyed by every parent's foreign key
at once (`WHERE id = ANY($1)`), then stitches results back onto their
parents in memory. `reporter` and `assignee` both arrive `.loaded`; every
other issue read this way still starts `.notLoaded`, exactly as the
previous exercise described.

## Why this is the exercise's whole point

Hangar's own benchmark suite measures the shape this design exists for:
loading 50 users' issues (4 each), batched, against the naive
one-query-per-parent alternative.

| | queries | time |
|---|---|---|
| batched preload | 2 | 2.24 ms |
| one query per parent | 1 + 50 | 11.10 ms |

**5×** — and the mechanism is exactly "N round trips become 2," not
something more exotic. That number is also a warning about benchmarking
itself: an earlier version of this same measurement used one user
reporting 1000 issues instead of 50 users reporting a few each, and under
that shape preload measured *slower* — both paths decoded the same ~1200
rows, so the one thing preloading actually saves (round trips) never
showed up. A batching optimization only earns its keep when there are
batches: many parents, not few.

## Tuning what gets preloaded

The second argument to `.preload` reaches into the child query — ordering,
filtering, or nesting another preload — without leaving the batched path:

```swift
Project.where { $0.id == projectID }
    .preload(\.issues) { $0.order { $0.updatedAt.desc() }.preload(\.reporter) }
```

Issues arrive sorted, and each issue's own reporter is preloaded too —
still two batched queries deeper, never a join, and still nothing lazy: an
`issue.reporter` you didn't ask for in that closure still throws exactly
as an un-preloaded association always does.

A many-to-many `@HasMany(through:)` association preloads the same way from
the call site — `.preload(\.watchers)` looks identical whether `watchers`
is direct or goes through a join table. Underneath, it's still never a SQL
join: one batched query against the join table, one against the related
table.
