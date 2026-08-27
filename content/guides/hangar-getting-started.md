---
title: "Hangar: Getting Started"
description: Models are structs, queries are values, and a typo in a column name is a compile error.
order: 10
category: Hangar
---

Hangar is a type-safe query layer for PostgreSQL, built directly on
PostgresNIO — no runtime reflection, no string-keyed column access. You
declare a model, and the same declaration gives you a typed query builder,
a typed insert, and a typed update.

## Declaring a model

```swift
import Hangar

@Entity("posts")
struct Post {
    @ID var id: UUID
    @Column var title: String
    @Column var viewCount: Int
    @BelongsTo(\.authorID) var author: Loadable<Author>
}
```

`@Entity("posts")` names the table. `@Column` maps `viewCount` to
`view_count` — snake_case is the default column-naming convention, and you
override it per property (`@Column("legacy_name")`) when a table doesn't
follow it. `@ID` marks the primary key. None of this is reflection: the
macro expands at compile time into a `Columns` type carrying real, typed
keypath-like accessors, which is what makes the next part possible.

## A query is a value

```swift
let popular = Post.where { $0.viewCount > 1_000 }
    .order { $0.viewCount.desc() }
    .limit(20)
```

Nothing executes yet. `popular` is a `Query<Post, Post>` — a value you can
pass around, store, extend, or hand to a function, and building it further
never mutates what it was built from:

```swift
let base = Post.where { $0.published == true }
let recent = base.order { $0.createdAt.desc() }.limit(10)
let mine = base.where { $0.authorID == currentUserID }   // `base` is unchanged
```

`$0.viewCount > 1_000` is not a string template — `$0` is the generated
`Columns` value, `.viewCount` is a real property access, and `>` is a real
operator overload building a `Predicate`. Misspell `viewCount` and the
build fails at that line, not at 2am when the query finally runs against
production.

## Running it

A query does nothing until a `Repo` runs it:

```swift
let repo = Repo(client: postgresClient, logger: logger)
let posts: [Post] = try await repo.all(popular)
```

`repo.one(query)` expects exactly one row and throws if it finds zero or
more than one — the right shape for "fetch by primary key," where "not
found" and "found two" are both bugs worth throwing over, not a `nil` the
caller has to remember to check twice.

## Seeing the SQL

Every query can show you exactly what it renders to, with no server
involved:

```swift
print(popular.debugSQL)
// SELECT "id", "title", "view_count", "author_id" FROM "posts"
// WHERE "view_count" > $1 ORDER BY "view_count" DESC LIMIT $2
```

`debugSQL` never contains a bound value — `$1`, `$2` are placeholders, the
same ones sent over the wire. That makes it safe to log, and it's the
single best debugging habit Hangar rewards: if a query returns the wrong
rows, `.debugSQL` almost always shows you why before you've touched a
debugger.

## Where to go next

- [Queries](/guides/hangar-queries) — predicates, joins, aggregates, and
  the projection shapes that decode straight into your own types.
- [Changesets](/guides/hangar-changesets) — validated, tracked writes:
  Hangar's answer to "what actually changed, and was it allowed to?"
- [Associations & Preloading](/guides/hangar-preloading) — why an
  association you forgot to load throws instead of quietly returning
  nothing, and how batched preloading avoids N+1 without a SQL join.

If you'd rather work through this interactively, [Part 2 of the
tutorial](/tutorial/02-data) builds the same ideas as runnable exercises,
with `debugSQL` output shown for every query as you write it.
