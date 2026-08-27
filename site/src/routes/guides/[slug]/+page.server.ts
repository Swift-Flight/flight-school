import { error } from '@sveltejs/kit';
import { loadDoc } from '$lib/server/content';
import { findGuide } from '$lib/guides';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const outline = findGuide(params.slug);
	if (!outline) {
		// Not in the manifest at all — a genuine 404, not a "coming soon".
		error(404, 'No such guide');
	}

	const doc = await loadDoc(`guides/${params.slug}.md`);
	return { outline, doc };
};
