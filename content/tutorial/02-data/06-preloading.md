---
title: Preloading and the N+1 story
description: The measured 5× — batched queries instead of one-per-parent.
order: 6
---

```swift
let posts = try await repo.all(
    Post.where { $0.published == true }
        .preload(\.author)
        .preload(\.comments))
```

Two associations, two extra queries total — never one per post. Each
`.preload` runs its own batched query keyed by every parent's foreign key
at once (`WHERE id = ANY($1)`), then stitches results back onto their
parents in memory. `author` and `comments` both arrive `.loaded`; every
other post read this way still starts `.notLoaded`, exactly as the previous
exercise described.

## Why this is the exercise's whole point

Hangar's own benchmark suite measures the shape this design exists for:
loading 50 authors' posts (4 each), batched, against the naive
one-query-per-parent alternative.

| | queries | time |
|---|---|---|
| batched preload | 2 | 2.24 ms |
| one query per parent | 1 + 50 | 11.10 ms |

**5×** — and the mechanism is exactly "N round trips become 2," not
something more exotic. That number is also a warning about benchmarking
itself: an earlier version of this same measurement used one author
owning 1000 posts instead of 50 authors owning a few each, and under that
shape preload measured *slower* — both paths decoded the same ~1200 rows,
so the one thing preloading actually saves (round trips) never showed up.
A batching optimization only earns its keep when there are batches: many
parents, not few.

## Tuning what gets preloaded

The second argument to `.preload` reaches into the child query — ordering,
filtering, or nesting another preload — without leaving the batched path:

```swift
Post.where { $0.published }
    .preload(\.comments) { $0.order { $0.createdAt.asc() }.preload(\.author) }
```

Comments arrive sorted, and each comment's own author is preloaded too —
still two batched queries deeper, never a join, and still nothing lazy: a
`comment.author` you didn't ask for in that closure still throws exactly as
an un-preloaded association always does.

A many-to-many `@HasMany(through:)` association preloads the same way from
the call site — `.preload(\.tags)` looks identical whether `tags` is direct
or goes through a join table. Underneath, it's still never a SQL join:
one batched query against the join table, one against the related table.
