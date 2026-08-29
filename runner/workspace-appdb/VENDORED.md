# Vendored from flight-cli

A verbatim copy of `templates/basics/` from
[flight-cli](https://github.com/Swift-Flight/flight-cli) — what
`flight new --tier basics` produces. It backs the `app+db` execution tier
(PLAN §3): a warm, prebuilt Flight application with a database behind it,
which is what Part 3's curriculum edits.

**Vendored from commit `be90caa`.**

flight-cli carries no tags, so there's no release boundary to pin against
and no version to compare — the commit hash is the only way to tell later
whether this copy has drifted. Re-vendor by copying the whole directory
again and updating that hash, rather than hand-patching files here: the
point of vendoring is that a learner meets the same project shape the CLI
would have given them, and a locally-edited copy stops being that.

That discipline earned its keep immediately. The first vendoring of this
template hit a real upstream bug — `GET /users` answered 500, "No
component registered for App.UserRepositoryProtocol", because
`@Repository` registers only the concrete type while the controllers
depend on the protocol seam. Rather than patch it here, it was fixed in
flight-cli (`be90caa`) and re-vendored, so every `flight new --tier basics`
user gets the fix too. See that commit for why the template's own tests
stayed green through it.

Two things here are *not* upstream, both deliberate:

- **`Package.resolved`** — the template doesn't ship one (a fresh
  `flight new` resolves on first build). This tier can't: the runner has no
  network egress except Postgres (PLAN §5), so dependency *source* has to
  be fetched at image-build time, which needs a pinned resolution.
  Regenerate with `swift package resolve` after re-vendoring.
- **This file.**

## How it reaches the session database

No template edit, and no `flight.yaml` change. `flight.yaml` names
`datasource.primary.url`, and Flight layers `FLIGHT_*` environment
variables over the file, so the runner sets
`FLIGHT_DATASOURCE_PRIMARY_URL` to the session's own database for the
app's process — exactly how `FLIGHT_SERVER_HOST` already overrides the
template's `127.0.0.1` bind. Verified by watching the pool open its five
connections against the intended database, not by reading the mapping.
