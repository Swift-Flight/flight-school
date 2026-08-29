# Flight School

An interactive tutorial and documentation site for
[Flight](https://github.com/Swift-Flight/flight),
[Hangar](https://github.com/Swift-Flight/hangar), and Changeset — in the
mold of [Svelte's tutorial](https://svelte.dev/tutorial), with a parallel
plain-documentation track written at the level of detail Phoenix and Ecto
readers expect.

Full design and rationale: [`PLAN.md`](PLAN.md). Current build status,
what's real vs. planned: [`STATUS.md`](STATUS.md).

## Structure

```
site/       Svelte 5 + SvelteKit — the frontend, guides + tutorial UI
content/    Markdown: tutorial exercises and plain-doc guides
scripts/    Content integrity checks, the DocC → Pages index generator
```

`server/` (a Flight backend for the interactive execution tiers) and
`runner/` (the sandboxed code-execution pool) are both real — see
`STATUS.md` for what's actually been verified end to end and what's still
open.

## Running locally

```bash
cd site
npm install
npm run dev
```

Or the full deployment shape:

```bash
docker compose up -d --build
```

**Pass `--build`.** Content lives in `content/` and is bind-mounted into
the site container, so editing a guide or exercise takes effect on the
next request with no rebuild. The site's own *code* is baked into the
image, and the two drift apart the moment a change touches both — which is
exactly what adding a new content shape does.

The failure mode is quiet rather than loud, so it's worth recognising: a
stale image can't read newer content, the loaders return nothing, and
every affected page renders a placeholder. Since M3 that placeholder says
so explicitly ("content present, but unreadable by this build") rather
than claiming the exercise is unwritten, but the fix is the same either
way — rebuild:

```bash
docker compose up -d --build site
```

The runner image is the expensive one (it warms a full SwiftPM build cache
per execution tier — roughly 25 minutes cold), so rebuild `site` on its
own when that's all that changed.

### Reach it on port 80, not the site's own port

`/api/*` and `/socket` are not SvelteKit routes — they belong to the
Flight backend in `server/`, and Caddy is what puts the two behind a
single origin. Open `http://localhost/`. Hitting the site container's own
port instead gets you perfectly working *pages* and a failure on every API
call, which reads as a broken endpoint rather than a wrong port; those
paths now answer `421 Misdirected Request` explaining as much, instead of
a bare 404.

`npm run dev` has no such problem — vite's dev proxy forwards `/api` and
`/socket` for exactly this reason.

### Testing the API by hand

Send a body, even an empty one: `curl -X POST -d '' http://localhost/api/session`.
A `curl -X POST` with no `-d` at all sends neither `Content-Length` nor a
body, and Caddy holds that request open rather than forwarding it — the
call appears to hang. The backend itself answers such a request fine when
reached directly, and browsers always set `Content-Length`, so this is a
hand-testing trap rather than something clients hit.

## Contributing content

Every markdown file under `content/` needs frontmatter (`title`,
`description`) and is checked by `scripts/check-content-links.py` in CI —
a broken relative link fails the build rather than shipping. New tutorial
exercises and guides also need an entry in `site/src/lib/curriculum.ts` or
`site/src/lib/guides.ts` respectively; that manifest is what lets the site
show a labeled "coming soon" placeholder for planned-but-unwritten content
instead of either faking it or 404ing.

## License

MIT. See [LICENSE](LICENSE).
