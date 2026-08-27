import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

// All SvelteKit/Svelte options (compilerOptions, preprocess, adapter) live
// in svelte.config.js — passing anything to sveltekit() here, even a single
// unrelated key, makes SvelteKit silently ignore svelte.config.js entirely
// (a real warning it prints, confirmed against the framework source: an
// adapter/preprocessor/runes-mode config that looked fine would otherwise
// have build in production with none of them applied).
export default defineConfig({
	plugins: [sveltekit()]
});
