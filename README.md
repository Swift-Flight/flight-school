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
`runner/` (the sandboxed code-execution pool) don't exist yet — see
`STATUS.md` for what M0 covers and what M1+ adds.

## Running locally

```bash
cd site
npm install
npm run dev
```

Or the full deployment shape:

```bash
docker compose up -d
```

Content lives in `content/` and is bind-mounted into the site container,
not baked into the image — editing a guide or exercise takes effect on the
next request, no rebuild needed.

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
