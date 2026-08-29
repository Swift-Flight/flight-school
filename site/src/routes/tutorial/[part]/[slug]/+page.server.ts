import { error } from '@sveltejs/kit';
import { adjacentExercises, findExercise } from '$lib/curriculum';
import { exerciseSourceExists, loadAppExercise, loadDoc, loadSnippet } from '$lib/server/content';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const found = findExercise(params.part, params.slug);
	if (!found) error(404, 'No such exercise');

	const runtime = found.part.runtime;

	// App-tier exercises live in a directory (README.md + meta.json +
	// app-a/app-b — PLAN §6), not a flat markdown file, so they're tried
	// first for those tiers and fall through to prose-only when the
	// directory isn't there. Most of Parts 1 and 3 still hasn't been
	// converted, as of M3 — see STATUS.md.
	const appExercise =
		runtime === 'app' || runtime === 'app+db'
			? await loadAppExercise(`tutorial/${params.part}/${params.slug}`)
			: null;

	// Only snippet-tier exercises have the single-file embedded editor
	// (M1's scope). `null` when the tier is right but the starting snippet
	// hasn't been authored yet.
	const snippet =
		runtime === 'snippet'
			? await loadSnippet(`tutorial/${params.part}/${params.slug}.swift`)
			: null;

	const doc = appExercise?.doc ?? (await loadDoc(`tutorial/${params.part}/${params.slug}.md`));
	const { prev, next } = adjacentExercises(params.part, params.slug);
	// Content on disk that we failed to render is a different problem from
	// content nobody has written — see `exerciseSourceExists`.
	const sourceExists = doc ? false : exerciseSourceExists(params.part, params.slug);
	return { ...found, doc, snippet, appExercise, sourceExists, prev, next };
};
