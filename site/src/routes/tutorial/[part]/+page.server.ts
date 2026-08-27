import { error } from '@sveltejs/kit';
import { findPart } from '$lib/curriculum';
import { docExists } from '$lib/server/content';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const part = findPart(params.part);
	if (!part) error(404, 'No such part');

	const written = part.exercises.map((ex) =>
		docExists(`tutorial/${part.slug}/${ex.slug}.md`)
	);

	return { part, written };
};
