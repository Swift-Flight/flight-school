# Status

What's actually built, verified, and running, versus what's still just in
`PLAN.md`. Updated as milestones land — see `PLAN.md` §10 for the full
milestone list this maps onto.

## Done (M0, in progress)

**Site.** SvelteKit 5 (Svelte `5.56.1`, verified — not just requested),
`adapter-node`, deployed via `docker compose up -d` (Caddy + site).
Content is markdown, bind-mounted into the container and read per-request
— editing a guide takes effect on the next request, no rebuild. The
exercise pager (`adjacentExercises` in `curriculum.ts`) walks the whole
curriculum flattened, not just the current part, so the last exercise of
one part correctly links into the first exercise of the next — verified
against a production build in both directions, and confirmed it composes
correctly with the "coming soon" placeholder below (a pager can point at
an unwritten exercise; that page still renders, with correct prev/next of
its own).

**Content, real and verified** — grounded directly in flight source and
flight-cli's actual templates/README, not invented:
- Part 0 (Setup), all four exercises: install, `flight new`, project
  anatomy, running locally.
- Part 1 (Flight basics), 8 of 9 exercises: bootstrap/modules, first
  route, path/query parameters, request bodies, responses/HTTPError,
  static assets, middleware, configuration. **`06-cookies` is deliberately
  unwritten** — cookie support landed in flight's source (commit
  `8997a5a`) but no release tag includes it yet (`v0.8.0` predates it), and
  `flight new`'s `Package.swift` resolves `from: "0.7.0"` to the latest
  *tagged* release. Writing this exercise now would document an API a
  learner's own `flight new` can't reach. Revisit once flight cuts its next
  tag; don't write it against `flight`'s HEAD in the meantime.
- Part 2 (Data with Hangar and Changeset), all 12 exercises: entities,
  queries, predicates/`debugSQL`, changesets, associations/`Loadable`,
  preloading, joins/aliases/self-joins, transactions/isolation/retry,
  `Multi`, bulk writes, `flight-data` (migrations/cache/Valkey), and
  diagnostics/`EXPLAIN`. Verified against Hangar `v0.2.1` and
  swift-changeset `v0.1.0` (tagged releases, not their working trees —
  both repos had unrelated in-progress uncommitted changes while this was
  written; tagged-source reads avoided depending on either).
- One guide: "Hangar: Getting Started."

**Real bugs found upstream while verifying, not fixed here** (out of
scope — those repos have their own in-progress work and their docs
aren't this repo's to edit): Hangar's committed `README.md` has a bare
`@Column var title: String` (the macro requires a string-literal name
whenever it's used at all — bare `@Column` is a compile error) and
`@BelongsTo(\.authorID)` (the macro requires the `foreignKey:` label; no
positional overload exists). `flight-data`'s `Docs/migrate.md` still
shows an old standalone-package install path
(`flight-server/flight-migrate`) that contradicts the current
`flight-data` trait-based one in its own top-level `README.md`. Every
Hangar/flight-data example in this repo's Part 2 content was checked
against the macro/API's actual requirements directly, not copied from
the affected passages.

Everything else in `PLAN.md` §7's curriculum outline exists only as a
title + description in `site/src/lib/curriculum.ts` / `guides.ts` — the
site renders those as a labeled "coming soon" placeholder, not a 404 and
not faked content. That distinction is load-bearing: check a slug against
the manifest before assuming it's written.

**CI**, all passing on real GitHub Actions runs (not just locally):
- `site.yml` — content link-checking (`scripts/check-content-links.py`,
  modeled on flight-cli's `verify-tutorial.sh`) + site type-check + build,
  on every push/PR.
- `docs.yml` — DocC → GitHub Pages for flight/hangar/flight-data.
  **Not yet run for real** (workflow_dispatch/weekly, and the three repos
  it clones need to exist at the refs it's given) — the DocC generation
  command and the index generator were each verified independently
  against real output, but the full workflow end-to-end, including the
  actual Pages deployment, has not executed yet. Do that before trusting
  it blindly the first time a real domain is wired up.

## Explicitly deviated from PLAN.md §6, on purpose

The plan's content layout has each exercise as a directory with
`README.md` + `meta.json` + `app-a/`/`app-b/` diffs against a CLI
template. What's actually here is flatter: one `.md` file per exercise
with frontmatter (`title`, `description`, `order`), no `app-a`/`app-b`
yet. That's not a missed detail — M0 is text-only, no code execution, so
there is no "starting files vs. solution files" to diff yet. The
`app-a`/`app-b` shape becomes real starting at M1 (the snippet runner),
where an exercise's editor needs actual starting content and a solution
to diff against. Revisit the content layout then; don't assume the
current flat files are the final shape.

## Not started

- `server/` (Flight backend — content API, session broker, channel-
  streamed build output). Referenced as comments in `docker-compose.yml`
  showing the intended shape, nothing implemented.
- `runner/` (the sandboxed execution pool). Same — commented shape only.
- Everything requiring either of the above: the snippet/db/app/app+db
  execution tiers, the embedded editor, "Solve" diffing, session
  presence, the preview proxy.
- Parts 3–4 of the curriculum (Parts 1 and 2 are written — see above), and
  every guide except "Hangar: Getting Started" — titles and descriptions
  exist in the manifests; the prose doesn't yet.
- Testing content specifically (Part 3) has no proven source to adapt
  from anywhere yet — flagged in `PLAN.md` §7a as a genuine open item,
  not just unwritten.

## If you're picking this up cold

Read `PLAN.md` first, all of it — §7a and §8a in particular record two
corrections made *after* the original plan was written, each from
actually checking a claim against source rather than trusting the first
draft. The pattern is worth continuing: before writing an exercise for
Parts 3–4, check whether flight-cli's `TUTORIAL.md` or `demo` tier
already covers that ground (per §7a, it covers more than the benchmark
app does), and don't assume a config/CLI flag/API shape without grepping
the real source first — this plan has already been wrong twice in ways
that only source-checking caught, and Hangar's own README turned out to
have two more (see above).

Before trusting any upstream package as a source of truth, check it's
not mid-edit: `git status --short` in that package's own checkout, and if
anything's uncommitted, read the tagged release (`git show
<tag>:path/to/file`) instead of the working tree for whatever you're
about to cite. Two sibling repos (Hangar, swift-changeset) had real
in-progress uncommitted work while Part 2 was written; reading their
working trees directly would have pulled in unreleased API shapes a
learner's own dependency resolution can't reach yet (exactly the
`06-cookies` situation above, just easier to miss one repo over).

One content-pipeline gotcha worth knowing before it costs you a debugging
session: **content is parsed at *request* time, never at build time** —
`npm run build`/`npm run check` typecheck the site's own code but never
touch a `.md` file's frontmatter, so a YAML mistake there (an unquoted
string containing `:`, say — caught once already, in
`02-data/12-diagnostics.md`'s frontmatter, before it shipped) passes both
cleanly and only breaks when the page is actually requested. Spot-check
new content against a real running server (`node build/index.js` with
`CONTENT_ROOT` set), not just the build/typecheck/link-check trio.
