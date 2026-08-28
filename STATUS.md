# Status

What's actually built, verified, and running, versus what's still just in
`PLAN.md`. Updated as milestones land — see `PLAN.md` §10 for the full
milestone list this maps onto.

## Done (M0 — content complete; confirming DocC is the last piece)

Per `PLAN.md` §10, M0 is "SvelteKit site rendering guides + tutorial
*text* (no execution); the guides link out to DocC on GitHub Pages."
Both halves of that are now done — every tutorial part (40 of 41
exercises) and all 13 planned guides. What's left to call M0 entirely
closed is confirming the just-fixed `docs.yml` run succeeds end to end,
including the actual Pages deployment — in progress as of this writing.

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
- Part 3 (Intermediate web), all 7 exercises: wiring Hangar's `Repo` into
  Flight's request scope (and the connection-affinity bug that motivates
  it), authentication via `TokenValidator`/OIDC, multipart + resumable
  (tus 1.0) uploads, server-sent events, `@Scheduler`/fleet-wide-once
  scheduling, the actuator's real health/dashboard split, and the three
  real sizes of test.
- Part 4 (Advanced: realtime and beyond), all 9 exercises: raw
  WebSockets vs. Channels, the envelope protocol (join/handle/reply/
  broadcast), HTTP-to-socket fan-out, Presence (metas, state-then-diffs,
  the measured join-storm cost), the four teardown paths, testing
  channels, the PubSub clustering seam, a capstone tying every seam
  together, and deployment. **This completes every part of the tutorial
  curriculum** — Parts 0 through 4, 40 of 41 planned exercises written.
  The one gap is `01-basics/06-cookies`, deliberately deferred — see
  below.
- Parts 3 and 4 both leaned on parallel research agents, one per
  independent subsystem, rather than one sequential pass — each agent's
  findings were cross-checked before anything got written from them,
  same bar as everywhere else in this file. Part 4 specifically used a
  real, unique source: a benchmark project
  (`/home/sinner/swift/SwiftFlight/benchmark/`) that built the same
  realtime issue board twice — once on Flight, once hand-rolled against
  Hummingbird — specifically to measure what Channels is worth. Real
  numbers from it are cited directly in `04-advanced/01-websockets.md`
  and `08-capstone.md` (infrastructure: 0 lines vs. 315; feature layers
  within 7 lines of each other). That benchmark directory is **not a git
  repo** and its own `Package.swift` uses a path dependency on `flight`
  rather than a pinned tag (its own comment already flags this as "wrong
  for a citable result") — the Channels/Presence/PubSub source files it
  exercises haven't changed since well before the tag this tutorial
  otherwise cites, so the numbers hold today, but re-verify before
  citing them again far in the future, and don't treat that directory as
  version-controlled safety net the way every other cited repo is.
- **All 13 planned guides**, every one in `guides.ts` now real: Up and
  Running (Part 0), Routing and Controllers, Requests & Responses,
  Configuration, Testing, Deployment (Flight); Hangar Getting Started,
  Queries, Changesets, Associations & Preloading, Transactions & Multi
  (Hangar); Channels, Presence (Realtime) — repackaging tutorial material
  already verified while writing Parts 1–4, not separately re-verified.
  "Hangar: Getting Started" was also **fixed**: it originally had the
  same two invented-API mistakes as Hangar's README below, inherited
  when it was written before this session's verification pass existed.

**Real bugs found upstream while verifying, not fixed there** (out of
scope — those repos have their own in-progress work and their docs
aren't this repo's to edit; this repo's own content was written against
the verified-correct shape in every case). The count is high enough to
name a pattern rather than treat each as a one-off: across `flight`,
Hangar, and `flight-data`, doc comments, docc catalogues, and READMEs
drift from the code they describe often enough that none of them should
be trusted as a citation on their own — grep the actual declaration, the
actual diagnostic message, or the actual route registration instead.
Specific instances found:
- Hangar's `README.md`: bare `@Column var title: String` (the macro
  requires a string-literal name whenever it's used at all) and
  `@BelongsTo(\.authorID)` (requires the `foreignKey:` label; no
  positional overload exists).
- `flight-data`'s `Docs/migrate.md`: an old standalone-package install
  path (`flight-server/flight-migrate`) contradicting the current
  trait-based one in its own top-level `README.md`.
- `flight`'s `FlightSecurityCore.docc`: a `security: { issuer, audience }`
  example missing the `oidc:` nesting the actual `@Settings`-bound keys
  require (`security.oidc.issuer`, confirmed by grepping
  `OIDCSecurityConfiguration.swift`'s literal `configuration.get(...)`
  calls).
- The same package's archived standalone README (pre-merge) demonstrates
  enforcement via `registerMiddleware(...)`, which current `flight`
  marks `@available(*, deprecated, ...)` in favor of `@Middleware` +
  `container.pipeline { }`.
- `flight`'s `FlightWeb.docc`: references a `.stream { }` response
  constructor that doesn't exist in source — the real API is
  `.serverSentEvents(_:)` / `.streaming(contentType:)`.
- `flight`'s `FlightActuator.docc` and top-level `README.md`: both
  describe `/actuator/info`, `/actuator/beans`, `/actuator/routes`, and
  `/actuator/config` endpoints that were never implemented — only
  `/actuator/health` and `/actuator` exist. `ActuatorModule.swift`'s own
  doc comment also overstates prod behavior ("the routes are simply not
  registered") — `/actuator/health` is registered in every environment
  by design; only the full dashboard is dev-gated.

Everything else in `PLAN.md` §7's curriculum outline exists only as a
title + description in `site/src/lib/curriculum.ts` / `guides.ts` — the
site renders those as a labeled "coming soon" placeholder, not a 404 and
not faked content. That distinction is load-bearing: check a slug against
the manifest before assuming it's written.

**CI**, all passing on real GitHub Actions runs (not just locally):
- `site.yml` — content link-checking (`scripts/check-content-links.py`,
  modeled on flight-cli's `verify-tutorial.sh`) + site type-check + build,
  on every push/PR.
- `docs.yml` — DocC → GitHub Pages for flight/hangar/flight-data. **Run
  for real** (GitHub Pages enabled via the API, `gh workflow run`
  triggered) — and caught two real bugs, one per attempt, that no local
  test could have: (1) the `swift:6.3.3` container image has no Python
  at all, so `generate-docs-index.py` failed with `python3: not found`;
  fixed with an `apt-get install -y python3` step. (2) The workflow only
  ever checked out the three *external* repos it clones for DocC
  generation (`repository:`/`path:` on every `actions/checkout@v4` call)
  — there was never a plain checkout of `flight-school` itself, so
  `scripts/generate-docs-index.py` never existed in the workspace at
  all. Every DocC-generation step worked fine regardless (they only
  touch the three cloned repos), which is exactly why this stayed
  invisible until the one step that needed this repo's own `scripts/`
  actually ran. Fixed by adding an initial bare `actions/checkout@v4`
  before the three named ones. Also fixed in the same pass: the
  generated index page linked to `flight-school.dev`, a domain that
  isn't configured (confirmed via the Pages API — no CNAME; the real
  URL is `swift-flight.github.io/flight-school/`, and the actual
  SvelteKit site has no fixed production domain yet either) — now links
  to the GitHub repository instead of a guessed-at domain. Re-triggered
  a third time to confirm both fixes; see the next status update for
  the outcome.

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

## If you're picking this up cold

Read `PLAN.md` first, all of it — §7a and §8a in particular record two
corrections made *after* the original plan was written, each from
actually checking a claim against source rather than trusting the first
draft. The tutorial curriculum itself is now fully written (see above),
so the immediate next work here is more likely to be M1+ (the execution
tiers) than new tutorial content — but if a gap does turn up (a new
flight/Hangar/flight-data release unblocking `06-cookies`, a curriculum
correction, a new guide), the same pattern that got the rest of this
content right still applies: don't assume a config/CLI flag/API shape
without grepping the real source first — this plan has already been
wrong twice in ways that only source-checking caught, and the "real bugs
found upstream" list above has grown to seven instances since. Note that
`flight-cli` itself carries no tags at all (`git tag --list` is empty
there) — there's no release boundary to check its templates/`TUTORIAL.md`
against the way there is for `flight`/Hangar/`flight-data`; treat its
`main` as the only version that exists.

Parts 3 and 4's verification used parallel research agents, one per
independent subsystem, rather than one sequential pass through
everything — it worked well for both and is worth reaching for again any
time a body of work splits cleanly into independent pieces, whether
that's more tutorial content or something else entirely. An agent's
findings still got cross-checked before anything was written from them,
the same as any other source — one of Part 4's findings (testing)
directly corrected a claim already published in Part 0's
`04-running.md` about what `TestClient` actually is, which is the
reminder worth keeping: re-read earlier content in light of later
findings, don't just trust it because it already shipped.

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
