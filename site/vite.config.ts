import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

// All SvelteKit/Svelte options (compilerOptions, preprocess, adapter) live
// in svelte.config.js — passing anything to sveltekit() here, even a single
// unrelated key, makes SvelteKit silently ignore svelte.config.js entirely
// (a real warning it prints, confirmed against the framework source: an
// adapter/preprocessor/runes-mode config that looked fine would otherwise
// have build in production with none of them applied).
// SERVER_ORIGIN: where `npm run dev` proxies /api and /socket to. In
// production Caddy does this proxying (see ../Caddyfile) in front of both
// services, so the site's own client code only ever calls same-origin
// relative paths — this dev-only proxy exists purely so `npm run dev`
// works standalone against a `server` running on the host, without also
// running Caddy in front of it.
const SERVER_ORIGIN = process.env.SERVER_ORIGIN ?? 'http://localhost:9100';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		proxy: {
			'/api': SERVER_ORIGIN,
			'/socket': { target: SERVER_ORIGIN, ws: true }
		}
	}
});
