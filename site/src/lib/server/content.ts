import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import matter from 'gray-matter';
import { Marked } from 'marked';
import { createHighlighter } from 'shiki';

// content/ lives at the repo root — site/../content — deliberately outside
// this SvelteKit project, so it can be shared with content-CI and (later)
// the runner image build without either depending on the site's build
// pipeline. See PLAN §6.
//
// This MUST be an env var with a dev-time fallback, not a relative climb
// from this file's own location: adapter-node bundles this module into
// build/server/chunks/ at a different, and not guaranteed stable, path
// depth than its source location — a relative `../../../../../content`
// resolves correctly under `vite dev` (where files run from their real
// source paths) and silently resolves to the wrong directory in the
// production build, where every page falls back to its "coming soon"
// state with no error. Caught by actually checking response *bodies*
// against the production build, not just status codes — a page that
// doesn't exist and a page whose content failed to load both return 200.
// The Dockerfile sets CONTENT_ROOT=/content to match where it copies
// content/ in the runtime image.
const CONTENT_ROOT =
	process.env.CONTENT_ROOT ??
	path.resolve(fileURLToPath(import.meta.url), '../../../../../content');

let highlighterPromise: ReturnType<typeof createHighlighter> | null = null;
async function highlighter() {
	// One shared highlighter instance: creating it is the expensive part
	// (loading grammars), highlighting with it is not. A module-level
	// singleton means the cost is paid once per server process, not once
	// per request.
	if (!highlighterPromise) {
		highlighterPromise = createHighlighter({
			themes: ['github-light', 'github-dark'],
			langs: ['swift', 'bash', 'yaml', 'json', 'sql', 'typescript', 'html', 'diff']
		});
	}
	return highlighterPromise;
}

let markedPromise: Promise<Marked> | null = null;
async function markedInstance(): Promise<Marked> {
	// A direct renderer.code override, not the marked-highlight plugin:
	// marked-highlight's `highlight()` callback is meant to return bare
	// token markup for insertion into marked's own <pre><code> wrapper,
	// but shiki's codeToHtml already returns a complete <pre> element —
	// running the two together nests a <pre> inside a <pre>. Overriding
	// the renderer directly replaces marked's wrapper outright instead.
	if (!markedPromise) {
		markedPromise = (async () => {
			const hl = await highlighter();
			const loaded = new Set(hl.getLoadedLanguages());
			const instance = new Marked({
				renderer: {
					code({ text, lang }) {
						const language = lang && loaded.has(lang) ? lang : 'text';
						return hl.codeToHtml(text, {
							lang: language,
							themes: { light: 'github-light', dark: 'github-dark' }
						});
					}
				}
			});
			return instance;
		})();
	}
	return markedPromise;
}

export interface RenderedDoc {
	title: string;
	description: string;
	html: string;
	frontmatter: Record<string, unknown>;
}

/** Cheap existence check against the same content root `loadDoc` reads from
 *  — for routes that need to know "is this written yet?" without paying
 *  for a full parse+render (e.g. a part's exercise list, marking which
 *  entries are live). */
export function docExists(relativePath: string): boolean {
	const fullPath = path.join(CONTENT_ROOT, relativePath);
	return fullPath.startsWith(CONTENT_ROOT) && existsSync(fullPath);
}

/**
 * Reads and renders one markdown file. Returns null if it doesn't exist —
 * callers decide what that means (a real 404, or a "coming soon" against
 * the curriculum/guides manifest — see routes/tutorial and routes/guides).
 */
export async function loadDoc(relativePath: string): Promise<RenderedDoc | null> {
	const fullPath = path.join(CONTENT_ROOT, relativePath);
	// Guard against the relative path escaping CONTENT_ROOT (e.g. via a
	// crafted route param containing `..`) before ever touching the
	// filesystem with it.
	if (!fullPath.startsWith(CONTENT_ROOT)) return null;
	if (!existsSync(fullPath)) return null;

	const raw = await readFile(fullPath, 'utf-8');
	const { data, content } = matter(raw);
	const md = await markedInstance();
	const html = await md.parse(content);

	return {
		title: (data.title as string) ?? relativePath,
		description: (data.description as string) ?? '',
		html,
		frontmatter: data
	};
}

/**
 * Reads a snippet exercise's starting code — a sibling `.swift` file next
 * to the exercise's `.md` (`02-data/03-predicates.md` → `03-predicates.swift`),
 * not `meta.json` + `app-a`/`app-b` per PLAN §6: that shape is for a
 * learner editing *files in a project*, which only the `app`/`app+db`
 * tiers need. A `snippet`-tier exercise is one file with no project
 * structure around it, so one sibling file is the whole shape M1 needs —
 * see STATUS.md's content-layout deviation note. Returns `null`, not an
 * error, when the exercise hasn't had starting content authored yet (most
 * of `runtime: snippet` still hasn't, as of M1) — callers render the
 * article without the editor in that case, the same "coming soon" posture
 * `loadDoc` already uses for missing prose.
 */
export async function loadSnippet(relativePath: string): Promise<string | null> {
	const fullPath = path.join(CONTENT_ROOT, relativePath);
	if (!fullPath.startsWith(CONTENT_ROOT)) return null;
	if (!existsSync(fullPath)) return null;
	return readFile(fullPath, 'utf-8');
}
