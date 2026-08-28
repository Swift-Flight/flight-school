import { error } from '@sveltejs/kit';
import { adjacentExercises, findExercise } from '$lib/curriculum';
import { loadDoc, loadSnippet } from '$lib/server/content';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const found = findExercise(params.part, params.slug);
	if (!found) error(404, 'No such exercise');

	const doc = await loadDoc(`tutorial/${params.part}/${params.slug}.md`);
	// Only snippet-tier exercises have an embedded editor (M1's scope —
	// see STATUS.md); other tiers' starting content is project files, a
	// different shape this route doesn't serve yet. `null` when the tier
	// is right but the starting snippet hasn't been authored yet — most of
	// Part 2 still hasn't, as of M1.
	const snippet =
		found.part.runtime === 'snippet'
			? await loadSnippet(`tutorial/${params.part}/${params.slug}.swift`)
			: null;
	const { prev, next } = adjacentExercises(params.part, params.slug);
	return { ...found, doc, snippet, prev, next };
};
