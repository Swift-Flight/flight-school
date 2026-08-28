---
title: Repo and first queries
description: A query is a value. Nothing runs until a Repo executes it.
order: 2
---

```swift
let query = Post.where { $0.published == true }
    .order { $0.viewCount.desc() }
    .limit(10)

let posts = try await repo.all(query)
```

`Post.where { }` is sugar for `Post.all.where { }` — `Post.all` is the
unfiltered query every chain starts from, whether you write it or not.
Every method on it — `where`, `order`, `limit` — returns a new `Query`
rather than changing anything, which is what makes the next part true.

## Nothing happens until `repo.all`/`repo.one`

`query` above is a value: building it runs no SQL at all. That means it can
be built in pieces, held onto, and reused — composing from a shared base
never disturbs the base itself:

```swift
let base = Post.where { $0.published == true }

let recent = base.order { $0.viewCount.desc() }.limit(10)
let popular = base.where { $0.viewCount > 1_000 }
```

`recent` and `popular` both start from `base`; neither mutates it, so
`base` is exactly as usable after both lines as before them. The `Repo` is
what actually reaches the database, and it comes in exactly two shapes
matched to what you're asking for:

```swift
let posts: [Post] = try await repo.all(query)      // every matching row
let post: Post? = try await repo.one(
    Post.where { $0.id == id })                     // zero or one
```

`one` returns `nil` for zero matches — "no post has that id" is an entirely
normal outcome, not an error. It throws only when a query meant to identify
a single row finds *more than one*, which is never legitimate: two rows
matching a query built to find one is a bug worth surfacing loudly, not a
`nil` indistinguishable from zero.
