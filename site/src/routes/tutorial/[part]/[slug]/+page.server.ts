import { error } from '@sveltejs/kit';
import { adjacentExercises, findExercise } from '$lib/curriculum';
import { exerciseSourceExists, loadExerciseDoc, loadSnippet } from '$lib/server/content';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const found = findExercise(params.part, params.slug);
	if (!found) error(404, 'No such exercise');

	// The embedded editor is the snippet tier only — see STATUS.md on why
	// the app tier was dropped. Every other tier is prose, with the code to
	// run locally in the article itself.
	const snippet =
		found.part.runtime === 'snippet'
			? await loadSnippet(`tutorial/${params.part}/${params.slug}.swift`)
			: null;

	const doc = await loadExerciseDoc(params.part, params.slug);
	const { prev, next } = adjacentExercises(params.part, params.slug);
	// Content on disk that we failed to render is a different problem from
	// content nobody has written — see `exerciseSourceExists`.
	const sourceExists = doc ? false : exerciseSourceExists(params.part, params.slug);
	return { ...found, doc, snippet, sourceExists, prev, next };
};
