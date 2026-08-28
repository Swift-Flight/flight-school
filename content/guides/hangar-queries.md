---
title: Queries
description: Predicates, joins, aggregates, and projections that decode into your own types.
order: 11
category: Hangar
---

A query is a value, composed from an entity's generated `Columns`:

```swift
let popular = Post.where { $0.published == true && $0.viewCount > 1_000 }
    .order { $0.viewCount.desc() }
    .limit(20)
```

`debugSQL` shows exactly what it renders to — every column listed
explicitly (never `SELECT *`), every value a `$n` placeholder, never a
literal:

```
SELECT "id", "title", "view_count", "published", "author_id" FROM "posts" WHERE (("published" = $1) AND ("view_count" > $2)) ORDER BY "view_count" DESC LIMIT 20
```

## Joins, aliases, and self-joins

```swift
Post.join(Comment.self, on: { post, comment in comment.postID == post.id })
    .select(into: Row.self) { post, comment in
        (title: post.title, commenter: comment.authorName)
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
Post.join(Comment.self, on: { p, c in c.postID == p.id })
    .join(Author.self, on: { _, comment, author in comment.authorID == author.id })
```

## Aggregates and projections

```swift
struct AuthorStats: Decodable { let authorID: UUID; let posts: Int; let views: Int }

try await repo.all(
    Post.groupBy { $0.authorID }
        .having { $0.viewCount.sum() > 1_000 }
        .select(into: AuthorStats.self) { p in
            (p.authorID, p.id.count(), p.viewCount.sum())
        })
```

`select(into:)` projects straight into any `Decodable` type — not just the
entity itself — for exactly the case a full model would over-fetch: an
aggregate, a narrow read, a join's combined row.

## Bulk writes

One statement, however many rows match:

```swift
let published = try await repo.update(Post.where { $0.published == false }) {
    ($0.published.set(to: true), $0.reviewedAt.set(to: Date()))
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
