<script lang="ts">
	import type { PageData } from './$types';
	let { data }: { data: PageData } = $props();

	let index = $derived(data.part.exercises.findIndex((e) => e.slug === data.exercise.slug));
	let prev = $derived(index > 0 ? data.part.exercises[index - 1] : null);
	let next = $derived(
		index >= 0 && index < data.part.exercises.length - 1 ? data.part.exercises[index + 1] : null
	);
</script>

<svelte:head>
	<title>{data.exercise.title} — Flight School</title>
</svelte:head>

<p class="crumb">
	<a href="/tutorial">Tutorial</a> / <a href="/tutorial/{data.part.slug}">{data.part.title}</a>
</p>

{#if data.doc}
	<article class="prose">
		<h1>{data.exercise.title}</h1>
		{@html data.doc.html}
	</article>
{:else}
	<div class="coming-soon">
		<p class="eyebrow">Coming soon</p>
		<h1>{data.exercise.title}</h1>
		<p class="desc">{data.exercise.description}</p>
		<p class="note">
			This exercise is planned but not written yet — tracked in
			<code>site/src/lib/curriculum.ts</code>.
		</p>
	</div>
{/if}

<nav class="pager">
	{#if prev}
		<a class="prev" href="/tutorial/{data.part.slug}/{prev.slug}">← {prev.title}</a>
	{:else}
		<span></span>
	{/if}
	{#if next}
		<a class="next" href="/tutorial/{data.part.slug}/{next.slug}">{next.title} →</a>
	{/if}
</nav>

<style>
	.crumb {
		font-size: 0.85rem;
		color: var(--muted);
	}
	.coming-soon {
		max-width: 60ch;
	}
	.eyebrow {
		text-transform: uppercase;
		letter-spacing: 0.06em;
		font-size: 0.8rem;
		color: var(--accent);
		font-weight: 700;
	}
	.desc {
		font-size: 1.1rem;
		color: var(--muted);
	}
	.note {
		font-size: 0.9rem;
		color: var(--muted);
		border-left: 3px solid var(--line);
		padding-left: 14px;
		margin-top: 24px;
	}
	.pager {
		display: flex;
		justify-content: space-between;
		margin-top: 48px;
		padding-top: 20px;
		border-top: 1px solid var(--line);
		font-size: 0.92rem;
	}
</style>
