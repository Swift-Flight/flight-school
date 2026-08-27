---
title: Multi
description: Units of work whose steps are decided before they run.
order: 9
---

`repo.transaction { }` is enough right up until the steps themselves need
to be conditional — at which point the closure body turns into a tangle of
nested `if`s around database calls. `Multi` is the alternative: a value
describing the steps, built before any of them run.

```swift
enum K {
    static let user = MultiKey<User>("user")
    static let profile = MultiKey<Profile>("profile")
}

var multi = Multi()
    .insert(K.user, userChangeset)
    .insert(K.profile) { results in
        profileChangeset(for: try results[K.user])
    }
if sendWelcome {
    multi = multi.run { results in
        try await mailer.sendWelcome(to: try results[K.user])
    }
}

switch try await repo.run(multi) {
case .success(let values):
    let user = try values[K.user]
case .failure(let failure):
    logger.error("step \(failure.key) failed: \(failure.error)")
}
```

Three things this buys over a plain transaction closure:

- **Steps are values.** `multi` above is built conditionally with an
  ordinary `if`, not by threading a flag through nested control flow inside
  a closure — build one in a function, return it, or combine two with
  `.merging(_:)`. Nothing runs until `repo.run(multi)`.
- **A later step reads an earlier one's result through a typed key** —
  `results[K.user]` is a `User`, not a dictionary lookup you cast by hand.
  `.insert(K.profile) { }`'s trailing closure exists specifically for this:
  the changeset it returns can depend on the row `K.user`'s step just
  inserted, in the same transaction, before either is committed.
- **A failed step is a value, not a thrown error.** `repo.run(multi)`
  returns a `MultiResult`, and `.failure` names which step broke
  (`failure.key`), what it threw (`failure.error`), and every result that
  had already completed (`failure.completed`) — all rolled back along with
  it. The thrown-error path stays reserved for the transaction machinery
  itself, so a handler never has to unwrap a generic error and guess which
  step produced it.

Every step runs inside one transaction — the same savepoint-nesting and
isolation rules the previous exercise covered apply here too, since `Multi`
is built on exactly that machinery, not a separate one.
