import adapter from '@sveltejs/adapter-node';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	compilerOptions: {
		// Force runes mode for the project, except for libraries.
		runes: ({ filename }) =>
			filename && filename.split(/[/\\]/).includes('node_modules') ? undefined : true
	},
	preprocess: vitePreprocess(),
	kit: {
		// adapter-node: this deploys as a standalone Node server behind Caddy
		// in the docker-compose stack (PLAN §9), not to a serverless platform.
		adapter: adapter()
	}
};

export default config;
