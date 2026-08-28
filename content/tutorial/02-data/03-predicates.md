---
title: Predicates as compiled Swift
description: debugSQL as a teaching device — see the SQL every query renders to.
order: 3
---

`{ $0.published == true && $0.viewCount > 100 }` isn't a string, and it
isn't interpreted at request time — it's ordinary Swift, operating on the
typed `Columns` the entity macro generated, building a small predicate tree
as a value. `debugSQL` renders that tree to see exactly what it became:

```swift
let query = Post.where { $0.published == true && $0.viewCount > 100 }
print(query.debugSQL)
```

```
SELECT "id", "title", "view_count", "published" FROM "posts" WHERE (("published" = $1) AND ("view_count" > $2))
```

(Wrapped here for width — `debugSQL` itself renders one line, not three, which
matters the first time you run this yourself and the output doesn't look like
the block above: it's not broken, it's just not wrapped.)

Three things worth noticing, all real properties of the renderer rather
than incidental formatting:

- **The column list is explicit, never `SELECT *`.** Every column the
  entity declared is named, in the order it was declared — adding a column
  to the struct later is the only way to add one here.
- **Every condition is parenthesized and every value is a placeholder.**
  `$1`, `$2`, … — never the literal `true` or `100`. `debugSQL` is safe to
  drop straight into a log line for exactly this reason: it shows the
  shape of the query, never the data that filled it.
- **`&&` became `AND`, in the order it was written.** Chained `.where { }`
  calls AND-combine the same way — narrowing a query one call at a time
  produces the same predicate tree as writing the whole condition at once.

## Why the placeholders matter more than they look

The binds themselves — `[true, 100]`, in order — travel separately from
this string, exactly the way `PostgresNIO` expects for a parameterized
query. `debugSQL` only ever shows you the first half. That split is what
makes a Hangar query immune to SQL injection by construction: there is no
code path where a value gets string-interpolated into the statement text,
because the text and the values are never in the same place until
PostgresNIO binds them at the wire.
