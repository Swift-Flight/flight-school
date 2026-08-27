import { error } from '@sveltejs/kit';
import { findExercise } from '$lib/curriculum';
import { loadDoc } from '$lib/server/content';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const found = findExercise(params.part, params.slug);
	if (!found) error(404, 'No such exercise');

	const doc = await loadDoc(`tutorial/${params.part}/${params.slug}.md`);
	return { ...found, doc };
};
