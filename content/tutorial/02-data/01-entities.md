---
title: "@Entity, @ID, @Column"
description: What the macro generates, and why a typo becomes a compile error.
order: 1
---

A table-backed model is a plain struct, three macros away from everything
Hangar needs to query it:

```swift
@Entity("issues")
struct Issue {
    @ID var id: UUID
    var projectID: UUID
    var title: String
    var status: String
}
```

`@Entity("issues")` names the table explicitly — Hangar never pluralizes or
guesses a table name from a type name, because guessing is wrong often
enough that typing it once is cheaper. `@ID` marks the primary key. Neither
`projectID`, `title`, nor `status` needs its own annotation: every plain
stored property becomes a column automatically, named by converting its
Swift name from `camelCase` to `snake_case` — `projectID` reads and writes
the `project_id` column without you saying so.

## `@Column`, only when the name actually needs overriding

A property whose name doesn't match its column gets an explicit one:

```swift
@Column("legacy_status") var status: String
```

That's the entire job `@Column` does — it takes no other form. Writing it
bare, with no name, is a compile error naming the site, not the property it
decorated silently doing nothing.

## What the macro actually generates

Four things, from that one `@Entity` line:

- **`Columns`**, a struct with one typed `Column<T>` per property —
  `Issue.Columns.status` — which is what a closure like
  `{ $0.status == "open" }` in the next exercise is actually a closure
  over. Reference a property that doesn't exist and the error is the same
  one you'd get misspelling any other member: `Issue.Columns` has no such
  property, caught before the build finishes.
- **`init(from: PostgresRow)`**, a positional row decoder generated at
  compile time — no reflection, no string-keyed dictionary lookup per row.
- **Table metadata** — the table name, the column list, which column is the
  primary key, and which columns are database-generated versus supplied on
  insert.
- **A memberwise initializer.** Swift stops synthesizing its own the moment
  the macro adds `init(from:)`, so `@Entity` writes the ordinary one back:
  `Issue(id: UUID(), projectID: UUID(), title: "…", status: "open")` still
  works exactly as it would on a struct with no macro at all.

None of this is reflection at request time — every part of it is decided
once, when the macro expands, which is also why a column that doesn't exist
is a build failure and not a query that silently returns the wrong thing.
