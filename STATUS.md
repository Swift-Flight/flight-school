# Status

What's actually built, verified, and running, versus what's still just in
`PLAN.md`. Updated as milestones land — see `PLAN.md` §10 for the full
milestone list this maps onto.

## Done — M0 fully closed, this time confirmed by real content, not status codes

Per `PLAN.md` §10, M0 is "SvelteKit site rendering guides + tutorial
*text* (no execution); the guides link out to DocC on GitHub Pages."
The tutorial (40 of 41 exercises) and all 13 guides are real and
confirmed working — see below, unchanged from before. The DocC-on-Pages
half is now genuinely confirmed too: after the fix below, checked that
the baked-in `baseUrl` on real deployed pages for all three repos
(`.../flight/FlightCore/`, `.../hangar/Hangar/`,
`.../flight-data/FlightCache/`) matches the real served path, and that
the actual JS asset each page requests resolves with 200 — not just the
top-level document. swift-changeset has since been added as a fourth
repo (a user noticed it was missing — Changeset/ValidationRule/
TableModel are taught directly in Part 2 but had no reference docs at
all) and is queued for its own first real run.

The DocC-on-Pages half was prematurely declared done here, twice, on
the strength of a verification pass that only checked HTTP status
codes. **Every DocC page was actually rendering blank** — reported
directly by a user, not caught by anything in this file's own process.
Root cause: DocC's `--transform-for-static-hosting` output is a
client-rendered SPA shell (`<div id="app"></div>`, empty until JS
populates it); the `--hosting-base-path` passed to DocC
(`flight-school/reference/flight/$target`) didn't match where the
artifact actually gets served (`flight-school/flight/$target` — no
`/reference/` segment, confirmed by checking the real generated file
layout and the index page's own links, both of which agreed with each
other and disagreed with the flag). Every JS/CSS asset the page needed
therefore 404'd, silently, and the page never became more than an empty
shell — a failure mode a status-code check cannot see, because the HTML
document itself still returns 200.

Worse: this workflow already *had* a step named "Smoke-check hosting
base path" meant to catch exactly this, and it didn't, because it only
grepped for the base-path string appearing *somewhere* in the output —
which is always true, since DocC bakes in whatever it's told whether or
not that's where the files end up. Replaced with a check that extracts
the real baked-in `baseUrl` from a generated page and confirms a
directory actually exists where it points; tested directly against
both the broken value (correctly fails) and the fixed one (correctly
passes) before trusting it in CI. Fixed and re-triggered; **not yet
re-verified against live rendered content** — the next update to this
file needs to confirm actual page content this time, not a status
code, before this can honestly be called done again.

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
  triggered) — and caught three real bugs across four attempts, none of
  which a local test could have: (1) the `swift:6.3.3` container image
  has no Python at all, so `generate-docs-index.py` failed with
  `python3: not found`; fixed with an `apt-get install -y python3`
  step. (2) The workflow only ever checked out the three *external*
  repos it clones for DocC generation (`repository:`/`path:` on every
  `actions/checkout@v4` call) — there was never a plain checkout of
  `flight-school` itself, so `scripts/generate-docs-index.py` never
  existed in the workspace at all. Every DocC-generation step worked
  fine regardless (they only touch the three cloned repos), which is
  exactly why this stayed invisible until the one step that needed this
  repo's own `scripts/` actually ran. Fixed by adding an initial bare
  `actions/checkout@v4` before the three named ones. Also fixed in the
  same pass: the generated index page linked to `flight-school.dev`, a
  domain that isn't configured (confirmed via the Pages API — no CNAME;
  the real URL is `swift-flight.github.io/flight-school/`, and the
  actual SvelteKit site has no fixed production domain yet either) —
  now links to the GitHub repository instead of a guessed-at domain.
  (3) **The serious one, found by a user, not by this process**: the
  third attempt was declared successful after only checking HTTP status
  codes on the index and one target page. Every DocC page was actually
  rendering blank — the `--hosting-base-path` baked into DocC's output
  (`flight-school/reference/flight/$target`) didn't match where the
  artifact is really served (`flight-school/flight/$target`, no
  `/reference/`), so every JS/CSS asset the page's client-rendered shell
  needs 404'd and `<div id="app">` never filled in. The workflow's own
  "Smoke-check hosting base path" step existed specifically to catch
  this and didn't, because it only grepped for the base-path string
  appearing *somewhere* in the output — always true, since DocC bakes
  in whatever it's told regardless of whether that's correct. Fixed the
  three `--hosting-base-path` values and replaced the smoke-check with
  one that extracts the real baked-in `baseUrl` and confirms a matching
  directory actually exists in the artifact — tested directly against
  both the broken and fixed values before trusting it in CI. **Deployed
  and confirmed for real**: curled the live pages for all three repos
  and checked that the baked-in `baseUrl` matches the real served path,
  and that the actual JS asset it requests resolves with 200 — the
  thing that was actually broken, not a status code on the outer HTML
  document. `swift-changeset` was added as a fourth repo immediately
  after (see above) and hasn't had its own deployed run yet.

## M1, well underway — the runner and the server

Per `PLAN.md` §10, M1 is "Snippet tier + Hangar/Changeset curriculum" —
the runner pool and channel-streamed output. Both halves of PLAN §4's
architecture now exist and have been verified talking to each other for
real: `runner/` (the sandboxed workspace + supervisor) below, and
`server/` (the sessions/execution Flight app that leases from the pool
and streams output to the browser over Channels) in the section after
it. `site/` still isn't wired to any of this yet — nothing here is
reachable by a learner through the actual deployed site, only through
direct HTTP/WebSocket calls to `server`, which is what verification used.

**What exists**: `runner/workspace` (a plain SwiftPM package — one
dependency, Hangar `0.2.1` — whose `exercise` executable target is the
one file a session is ever allowed to write to,
`Sources/exercise/main.swift`), `runner/supervisor` (a Flight app — yes,
this project dogfoods the framework it teaches even here — exposing
`/lease`, `/write`, `/run` (SSE-streamed build/run output), `/reset`,
`/release`), and `runner/Dockerfile` + `runner/entrypoint.sh` packaging
both into the sandboxed image PLAN §5 describes.

**Verified, not assumed** — the full lease → write → run → reset →
release cycle, tested against: the raw compiled supervisor binary; a
plain `docker run` of the built image; and the fully hardened
configuration — `--read-only`, tmpfs-mounted `/workspace` and `/tmp`,
`no-new-privileges`, a `pids-limit`, a memory ceiling, and full network
isolation (`--network none`) for the build itself. Real `debugSQL`
output came back correctly through the whole stack every time
(`SELECT "id", "total" FROM "orders" WHERE ("total" > $1)` for a
learner-written `@Entity` snippet, to pick one).

**Ten real bugs found by actually running this, not by writing it
carefully** — every one would have been invisible to a code review, and
each is the kind of thing "the plan already specified this" cannot
substitute for checking:

1. **`swift`'s path was hardcoded to `/usr/bin/swift`**, which doesn't
   exist on a Swiftly-managed install (this dev machine's own toolchain
   lives elsewhere). Fixed by resolving it through `env` instead of a
   guessed absolute path.
2. **The wall-clock timeout didn't actually kill anything.** A learner
   snippet using `@Entity` + `while true {}` survived `Process.terminate()`
   (SIGTERM) — confirmed this wasn't a Foundation bug by trying a bare
   `kill -TERM` from the shell against the same PID, which *also* failed.
   Whatever installs this behavior (almost certainly something in
   Hangar's SwiftNIO dependency chain, though the exact mechanism wasn't
   chased further — a bare Swift program with no such dependencies
   terminated on SIGTERM immediately) doesn't matter for the fix: the
   supervisor now escalates to SIGKILL, which cannot be caught or
   ignored, after a short grace period. Without this, the single most
   important safety property of the whole runner — a hung or malicious
   snippet gets killed, not trusted to finish — silently did not hold.
3. **A root-owned `/tmp` lock file broke every build as the runtime
   user.** The image's workspace was originally built as root, before
   `USER runner`; SwiftPM's lock file under `/tmp` came out root-owned,
   and the actual runtime user got "invalid access" on every build.
   Fixed by fixing ownership *before* building, so the same user builds
   and runs throughout.
4. **A `.build` baked at image-build time is unusable if the container's
   first build after starting doesn't trust it** — verified directly:
   the first `swift build` inside a freshly started container from an
   image with a prebaked `.build` recompiled everything from scratch
   (896 tasks, ~60s) instead of the ~2s incremental rebuild one changed
   file should cost, almost certainly Docker's layer export/import
   normalizing timestamps in a way that breaks SwiftPM's staleness
   detection across that boundary. A *second* build, live within the
   same running container, was correctly fast. Fixed by having the
   supervisor run its own warm-up build at startup, before the HTTP
   server even starts listening — paid once per container lifetime
   (containers are recycled after many leases, not per session), never
   by a learner's own first request.
5. **The tmpfs mount's `uid=`/`gid=` didn't match the image's real
   user** — guessed 1000 (the common default); the image's `useradd`
   actually assigned 1001. Fixed by pinning an explicit, stable uid/gid
   in the Dockerfile (10001) rather than depending on an implementation
   detail of one base image's `useradd` defaults, so anything
   orchestrating this container has a fixed number to depend on.
6. **Docker's tmpfs mounts are `noexec` by default**, and SwiftPM
   compiles and executes a temporary manifest-evaluation binary under
   `/tmp` on every build — every build failed with "Permission denied"
   until `exec` was added to both tmpfs mount options.
7. **A read-only rootfs breaks SwiftPM/Clang's own caches**
   (`~/.swiftpm`, `~/.cache/org.swift.swiftpm`,
   `~/.cache/clang/ModuleCache`), which live under `/home/runner` by
   default — not just the workspace. Fixed by redirecting `HOME` into
   the already-writable workspace tmpfs rather than adding a second
   mount.
8. **A network-isolated runner cannot `git clone` its own dependencies**
   — removing the (unusable, per #4) prebaked `.build` entirely and
   relying on the runtime warm-up build to fetch Hangar/PostgresNIO/NIO
   from the network directly contradicts "no network egress" (PLAN §5).
   Fixed by baking dependency *source* into the image via
   `swift package resolve` (fetches `.build/checkouts`, compiles
   nothing — carries none of #4's path sensitivity) at image-build time,
   so the runtime warm-up build only ever needs to *compile*, never
   fetch.
9. **`--pids-limit 128`** (a reasonable bound against a learner's
   fork-bomb) **is too tight for `swift build`'s own parallelism** —
   the warm-up build hit `posix_spawn: Resource temporarily unavailable`
   compiling SwiftSyntax/BoringSSL. Raised to 512 for this pass; the
   real fix (not yet done) is capping `swift build`'s own `-j` inside
   the supervisor so resource needs stay predictable regardless of what
   limit is configured, rather than just raising the limit until a
   from-scratch build happens to fit.
10. **A 2GB memory ceiling OOM-killed the warm-up build** under `--cpus
   2.0` (less headroom than an unconstrained build gets from more
   parallelism finishing faster). Raised to 4GB. The warm-up genuinely
   took ~14 minutes under the full hardened resource profile — a real,
   one-time-per-container-lifetime cost, not something a learner
   session ever waits on, but worth knowing before assuming "read-only
   + tmpfs + tight limits" is free.

**Not yet done here**: `docker-compose.yml`'s `runner` entry originally
used `deploy: replicas: 4` on one service — wrong, caught while building
the server on top of it (see below), now four named `runner-1`..`runner-4`
services instead. That, and everything else in this section, has been
validated with `docker compose config` and directly with `docker
build`/`docker run` against one runner at a time, but **not yet brought
up as the full multi-runner `docker compose up` stack** — see the
server section's own "not yet done" for the composite gap this leaves.
A custom seccomp profile (PLAN §5 calls for "seccomp default profile,"
which Docker already applies without any extra configuration — a
*tighter*, purpose-built profile is a real hardening step still open)
and `swift build -j` capping (see #9) are the two concrete follow-ups
worth doing before trusting this at real learner-facing scale.

## M1 continued — the server

The sessions/execution half of PLAN §4: `server/` is a Flight app —
`SessionBroker` (an actor holding pure in-memory pool/lease state: which
runners are free, which session holds which lease, when it was last
touched), `RunnerClient` (an `AsyncHTTPClient`-based caller of one
runner's `/lease`/`/write`/`/run`/`/reset`/`/release`, including a
from-scratch SSE parser for `/run`'s streamed output — nothing in Flight
consumes an SSE stream, only produces one, so this had to be written
against `ServerSentEvent.encoded`'s wire format directly), `SessionService`
(composes the two and fans `/run`'s output out to a `session:<id>`
Channel topic via `ChannelBroadcaster`, resolved with
`context.resolve(ChannelBroadcaster.self)` exactly the way
`benchmark/flight-app`'s `IssueController` already does it), a
`SessionController` (`@Controller`, `/api/session`, `/api/session/write`,
`/api/session/run`, `/api/session/reset`), a `SessionChannel` (join gate
for `session:*` — rejects a socket unless the topic's session id is
currently live), and `SessionReaperService` (the idle-TTL/hard-cap
reaper PLAN §4 calls for, structured the same way
`FlightPresenceModule`/`PresenceService` are: a `final class` module that
stashes the post-freeze container so its `Service` can resolve from it —
the shape any service-owning module needs, confirmed by reading that
real precedent rather than guessing at the `FlightModule.service` seam).

**Verified end to end against a real runner container**, not just
compiled: created a session, wrote a real `@Entity`-bearing Hangar
snippet, joined `session:<id>` over the WebSocket channel socket, called
`/api/session/run`, and watched the actual build output and
`debugSQL` line arrive as channel pushes —
`SELECT "id", "total" FROM "orders" WHERE ("total" > $1)` for a
hand-written `Order.where { $0.total > 100 }` snippet, streamed live,
not polled. Also verified: reusing an existing session id is idempotent;
`/write`/`/run`/`/reset` without a session id is rejected (400); joining
a channel topic for an unknown session id is rejected
(`flight:error`/`forbidden`); a failed runner lease correctly returns
the claimed runner to the free pool rather than losing it
(`SessionBroker.unclaim`); and, with the idle timeout and reap interval
turned down to a few seconds for the test, the reaper actually expires
an idle session, releases its runner lease back to the supervisor,
pushes a `session_expired` event to a still-connected socket, and frees
the runner for a brand new session to claim immediately after.

**Two real findings from building this, not from writing it carefully:**

1. **PLAN §4's "anonymous id (cookie)" isn't reachable yet.**
   `Cookie`/`Set-Cookie` support landed on flight's `main`
   (`8997a5a`, "Add cookie support") *after* the `v0.8.0` tag this
   package resolves against — checked directly (`git log
   v0.8.0..HEAD` in the flight checkout, plus confirming that checkout
   had *other* uncommitted changes sitting in its working tree, which is
   exactly the "don't read a dependency's mid-edit working tree" trap
   the tutorial-content work below already learned once). Session
   identity travels in an `X-Session-Id` header instead — the same
   security shape PLAN's cookie design has anyway (v1 has no accounts;
   knowing the session id already is the credential), just held by the
   client's own JS rather than the browser's cookie jar. Revisit once
   flight cuts a release past `v0.8.0`.
2. **A replicated Compose service can't be leased into.** The `runner`
   entry in `docker-compose.yml` used `deploy: replicas: 4` on one
   service — which round-robins one shared hostname across containers
   via Docker's embedded DNS, so there's no stable name to pin a
   session's lease to one specific container for the session's whole
   lifetime. The Caddyfile already assumed named `runner-1`/`runner-2`/…
   services for exactly this reason (its own `/preview/N/*` comment, from
   before the runner even existed) — the compose file just hadn't been
   brought in line with it yet. Fixed with four named services sharing
   one hardening block via a YAML anchor, confirmed by inspecting
   `docker compose config`'s resolved output, not just eyeballing the
   YAML merge syntax.

**Also caught while wiring Caddy's `/api/*` and `/socket` routes**: a
`handle_path /api/*` block strips the matched prefix before proxying,
which would have forwarded `/api/session/write` to the server as
`/session/write` — a 404, since the server's routes are literally
`/api/session*`. Caught by running `caddy adapt` against the real
Caddyfile and reading the emitted route JSON (`strip_path_prefix` was
right there), not by assuming `handle_path` behaves like `handle`.
Fixed by using plain `handle` for both new blocks; the same `caddy
adapt` output also confirmed both new routes land ahead of the
catch-all `reverse_proxy site:3000` in Caddy's evaluated route order,
which was the other thing worth not just assuming from file order alone.

**Not yet done**: the full stack — `caddy` + `site` + `server` + all
four named runners — has never been brought up together via one `docker
compose up`; verification here used a single `docker run` runner
container and `swift run Server` on the host, pointed at it directly.
Also open: a `server` restart drops `SessionBroker`'s in-memory lease
map, but a runner's own lease state survives independently (its
supervisor still thinks it's leased) — so a server crash or redeploy
while sessions are live orphans those runners until something resets or
restarts them, since nothing reconciles "who does the runner think holds
it" against a fresh broker's empty state. Acceptable for v1's "sessions
are disposable" posture, but a real gap, not a hidden one. Neither
`runner/` nor `server/` has a CI build/test step yet (`.github/workflows/`
still only has `docs.yml` and `site.yml`) — everything above was verified
by hand, the same way the runner's own hardening was.

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

- `server/`'s *content* module (PLAN §4: serving compiled exercise/guide
  JSON from a build-time manifest) — `site` still reads `content/`
  directly and per-request (`site/src/lib/server/content.ts`); nothing
  has forced that to change yet, and PLAN's own content-layout deviation
  (below) means the `app-a`/`app-b` shape a real content API would serve
  doesn't exist yet either.
- Everything in `site/` that would actually let a learner reach the
  runner/server work above: the embedded editor, wiring the tutorial UI
  to `/api/session*` and the `/socket` channel, "Solve" diffing, session
  presence, the preview proxy, and the `db`/`app`/`app+db` execution
  tiers (PLAN §3) beyond the no-DB snippet tier verified above.

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

**A status code is not proof of content, full stop — this was learned
twice in one session and is worth stating as a hard rule now rather than
trusting it'll stick after one example.** The first time (above) was the
production `CONTENT_ROOT` bug: a missing page and a broken content load
both return 200. The second time was worse, because it involved a *live*
deployment declared done on exactly this mistake: every DocC page on
GitHub Pages was rendering completely blank — a client-side SPA shell
whose JS 404'd because of a hosting-base-path mismatch — while the HTML
document itself still answered 200 the whole time. A user found it; the
verification pass that declared the DocC deploy "confirmed working" had
checked only `curl -o /dev/null -w "%{http_code}"` against the index and
one target page. The fix: when a page can render blank/wrong while still
returning 200 — anything with client-side rendering, a JS-populated
shell, or content loaded after the initial response — the check has to
look at what the page actually contains (grep the body for expected
text, or for a client-rendered page, check that its actual asset URLs
resolve), never the status code alone.
