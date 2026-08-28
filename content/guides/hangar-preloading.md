---
title: Associations & Preloading
description: Why unloaded throws, and how batched preloading avoids N+1.
order: 13
category: Hangar
---

An association's property type is `Loadable<T>`, never `T` directly:

```swift
@Entity("posts")
struct Post {
    @ID var id: UUID
    @BelongsTo(foreignKey: \.authorID) var author: Loadable<Author>
    @HasMany(foreignKey: \Comment.postID) var comments: Loadable<[Comment]>
}
```

Every association starts `.notLoaded`, carrying its own name, until
something explicitly preloads it. Reading through one that wasn't is not a
silent `nil` and not a lazy query fired on first touch:

```swift
let name = try post.author.get().name   // HangarError.notPreloaded("author") if nobody preloaded it
```

That's deliberate: lazy loading turns a missing preload into an invisible
N+1 that shows up as a production latency graph, sometimes years later.
Here, a handler that forgot to preload fails on its first execution,
deterministically — any test that exercises the path catches it.
`.optional` and `.isLoaded` are the non-throwing escape hatches for the
places absence genuinely is fine.

A nullable foreign key is `Loadable<Author?>`, not a special case:
`.notLoaded` still means "nobody asked," `.loaded(nil)` means "fetched, and
there is genuinely no author" — a different fact, which is also why
`Loadable` only conforms to `Encodable`, never `Decodable`: on the wire,
`null` could never tell those two apart on the way back in.

## Preloading batches instead of looping

```swift
let posts = try await repo.all(
    Post.where { $0.published == true }
        .preload(\.author)
        .preload(\.comments))
```

Two associations, two extra queries total — never one per post. Each
`.preload` runs one query keyed by every parent's foreign key at once
(`WHERE id = ANY($1)`), then stitches results back in memory. Hangar's own
benchmark suite measures the shape this exists for: 50 authors' posts,
batched, is **2.24ms**; one query per parent (1 + 50 queries) is
**11.10ms** — roughly 5×, and the mechanism is exactly "N round trips
become 2," nothing more exotic.

The second argument tunes the child query without leaving the batched
path:

```swift
Post.where { $0.published }
    .preload(\.comments) { $0.order { $0.createdAt.asc() }.preload(\.author) }
```

A many-to-many `@HasMany(through:)` association preloads identically from
the call site — still never a SQL join, just one batched query against the
join table and one against the related table.

## Catching a preload you missed

```swift
var repo = Repo(client: pool, logger: logger)
repo.diagnostics = .recommended   // 200ms slow-query threshold, 20 repeats

try await repo.detectingRepeatedQueries {
    try await renderDashboard()
}
```

If the same statement shape runs 20+ times in that closure, the logger
gets a warning naming the SQL, the count, and the fix — the safety net for
the day a `.preload` gets missed in code nobody thought to suspect.

## Where to go next

- [Queries](/guides/hangar-queries) — joins, for when the shape you need
  actually is a single combined row rather than parent-and-children.
- [Changesets](/guides/hangar-changesets) — validated writes to the models
  these associations hang off of.

[Part 2 of the tutorial](/tutorial/02-data/05-associations) builds this as
two runnable exercises, prev/next-connected to the rest of the part.
