# Status

What's actually built, verified, and running, versus what's still just in
`PLAN.md`. Updated as milestones land — see `PLAN.md` §10 for the full
milestone list this maps onto.

## Done (M0, in progress)

**Site.** SvelteKit 5 (Svelte `5.56.1`, verified — not just requested),
`adapter-node`, deployed via `docker compose up -d` (Caddy + site).
Content is markdown, bind-mounted into the container and read per-request
— editing a guide takes effect on the next request, no rebuild.

**Content, real and verified** — grounded directly in flight-cli's actual
templates/README, not invented:
- Part 0 (Setup), all four exercises: install, `flight new`, project
  anatomy, running locally.
- One guide: "Hangar: Getting Started."

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
- Parts 1–4 of the curriculum, and every guide except "Hangar: Getting
  Started" — titles and descriptions exist in the manifests; the prose
  doesn't yet.
- Testing content specifically (Part 3) has no proven source to adapt
  from anywhere yet — flagged in `PLAN.md` §7a as a genuine open item,
  not just unwritten.

## If you're picking this up cold

Read `PLAN.md` first, all of it — §7a and §8a in particular record two
corrections made *after* the original plan was written, each from
actually checking a claim against source rather than trusting the first
draft. The pattern is worth continuing: before writing an exercise for
Parts 1–4, check whether flight-cli's `TUTORIAL.md` or `demo` tier
already covers that ground (per §7a, it covers more than the benchmark
app does), and don't assume a config/CLI flag/API shape without grepping
the real source first — this plan has already been wrong twice in ways
that only source-checking caught.
