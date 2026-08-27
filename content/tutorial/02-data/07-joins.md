---
title: Joins, aliases, self-joins
description: Two-table, three-table, and the same table joined to itself.
order: 7
---

```swift
let rows = try await repo.all(
    Post.join(Comment.self, on: { post, comment in comment.postID == post.id })
        .select(into: Row.self) { post, comment in
            (title: post.title, commenter: comment.authorName)
        })
```

`.join`'s closure receives both sides' typed columns — `comment.postID`,
not a string, so a typo in either name is the same compile error a typo in
a single-table `where` would be. `.leftJoin` is the identical shape for
"every post, matched or not" instead of "only posts with a comment."

## The same table, twice

A join needs its two `FROM` entries to have distinct names — obvious for
`Post` and `Comment`, impossible by default for `Employee` joined to
`Employee`, since every column reference would be ambiguous. `.alias(_:)`
is how you give one side (or both) a name of its own:

```swift
Employee.alias("manager").join(Employee.alias("report"),
    on: { manager, report in report.managerID == manager.id })
```

Forget the alias and join a table to itself anyway, and it fails when the
query renders — not a generic ambiguity error, but one naming the exact fix:

```
a self-join needs an alias on at least one side:
Employee.alias("parent").join(Employee.alias("child"), on: ...).
```

Closures after an aliased join see alias-qualified columns throughout, so
`.where { manager, _ in manager.title == "VP" }` keeps working exactly like
it would on an unaliased join.

## A third table

Joining again on a two-table `JoinedQuery` gives its closure all three
column sets, in order:

```swift
Post.join(Comment.self, on: { p, c in c.postID == p.id })
    .join(Author.self, on: { _, comment, author in comment.authorID == author.id })
    .select(into: Row.self) { p, c, a in (title: p.title, commenter: a.name) }
```

This is ordinary generics — `JoinedQuery3<A, B, C, Result>` — rather than a
variadic form that joined an arbitrary number of tables. Three tables is
what a real query needs often enough to deserve its own type; a query
needing a fourth reaches for a subquery or a second round trip instead of
a `JoinedQuery4` nobody asked for.
