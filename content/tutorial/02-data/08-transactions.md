---
title: Transactions, savepoints, isolation, retry
description: Nested transactions become savepoints; serialization failures can retry themselves.
order: 8
---

```swift
try await repo.transaction { tx in
    try await tx.insert(issue)
    try await tx.transaction { inner in
        try await inner.update(                       // SAVEPOINT, not a new BEGIN
            Changeset(original: project).change(\.nextIssueNumber, nextNumber + 1))
    }
}
```

`transaction { }` hands the closure a `Repo` bound to that transaction's
own connection — every call on `tx` runs on it, not a fresh connection from
the pool. Calling `.transaction { }` again on a `Repo` that's already
inside one doesn't open a second transaction; Postgres doesn't nest
`BEGIN`, so it opens a `SAVEPOINT` instead, transparently. The body throwing
rolls back exactly that savepoint — the outer transaction, and whatever it
already did (the new issue, still uncommitted), is unaffected.

## Isolation level

```swift
try await repo.transaction(isolation: .serializable) { tx in
    ...
}
```

`isolation:` applies to the outermost `BEGIN` — `.readCommitted`,
`.repeatableRead`, or `.serializable`. A nested call's own `isolation:`
argument is ignored (Postgres ties the level to the whole transaction; a
savepoint can't change it), so it only ever needs setting once, where the
transaction actually starts.

## Retrying a serialization failure

`SERIALIZABLE` sometimes rejects a transaction outright when two run
concurrently against overlapping rows — SQLSTATE `40001`, or `40P01` for a
detected deadlock. Both are the isolation level working as designed: two
people claiming the same open issue at once is exactly this shape, and the
documented remedy is simply to run the whole thing again:

```swift
struct IssueNotFound: Error {}

try await repo.transaction(
    isolation: .serializable, retryingOnSerializationFailure: 3
) { tx in
    guard let issue = try await tx.one(Issue.where { $0.id == issueID }) else {
        throw IssueNotFound()
    }
    try await tx.update(Changeset(original: issue).change(\.assigneeID, currentUserID))
}
```

Two things worth being deliberate about before reaching for this:

- **The body must be safe to run more than once.** It will run again, on a
  fresh transaction, every time Postgres reports one of those two SQLSTATEs
  short of the attempt limit. A side effect outside the database — a sent
  email, an enqueued job — does not roll back with the transaction, so keep
  those out of a retried body, or the retry that saves the write duplicates
  the email.
- **Only the outermost transaction retries.** Calling the retrying form on
  a `Repo` already inside a transaction doesn't retry anything — a
  serialization failure dooms the whole transaction, and only whoever
  opened it can run it again.
