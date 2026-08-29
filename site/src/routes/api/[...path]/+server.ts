import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

// `/api/*` and `/socket` are not SvelteKit routes at all — they belong to
// the Flight backend (`server/`), and Caddy is what puts the two behind one
// origin (see ../../../../../Caddyfile). Reaching the site's own port
// directly therefore gets you working pages and a 404 on every API call,
// which reads as "the endpoint is broken" rather than "you're on the wrong
// port" — the pages rendering fine is exactly what makes it confusing.
//
// This exists to say so. It cannot proxy: the site container has no
// business knowing the backend's address, and inventing one here would
// give the app two different ways to reach it that could disagree.
const explain =
	'The /api routes are served by the Flight backend, not by SvelteKit. ' +
	'Reach the site through Caddy (http://localhost/ in the default compose ' +
	'setup, or `npm run dev`, whose vite proxy forwards /api and /socket) ' +
	'rather than the site container port directly.';

const handler: RequestHandler = () => error(421, explain);

export const GET = handler;
export const POST = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
