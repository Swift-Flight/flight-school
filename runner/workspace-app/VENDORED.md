# Vendored from flight-cli

This directory is a verbatim copy of `templates/skeleton/` from
[flight-cli](https://github.com/Swift-Flight/flight-cli), the same template
`flight new --tier skeleton` produces. It backs the `app` execution tier
(PLAN §3): the warm, prebuilt Flight application a learner's edits land in.

**Vendored from commit `2f315f3eed6a2069ed2a6be8a0fced6571321e74`.**

flight-cli carries no tags at all, so there's no release boundary to pin
against and no version to compare — the commit hash above is the only way to
tell later whether this copy has drifted from upstream. Re-vendor by copying
the whole directory again and updating that hash, rather than hand-patching
individual files: the point of vendoring is that a learner meets the same
project shape the CLI would have given them, and a locally-edited copy stops
being that.

Two things here are *not* upstream, both deliberate:

- **`Package.resolved`** — the template doesn't ship one (a fresh
  `flight new` resolves on first build). This tier can't: the runner has no
  network egress except Postgres (PLAN §5), so dependency *source* has to be
  fetched at image-build time, which needs a pinned resolution. Regenerate
  with `swift package resolve` after re-vendoring.
- **This file.**

No trait rewriting is applied. `flight-cli`'s `TraitRewriter` only edits the
manifest when a capability (Postgres/Valkey/Security) is requested, and the
`app` tier requests none — an `app+db` tier later would need that machinery,
or its own vendored template.
