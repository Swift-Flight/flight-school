<script lang="ts">
	// The snippet tier's embedded editor (PLAN §3/§4): CodeMirror 6 with the
	// community Swift legacy-mode for highlighting (no LSP in v1 — see
	// PLAN §4's reasoning), a Run button that writes the buffer and starts a
	// build+run on the leased runner, and an output pane fed by the
	// `session:<id>` channel this component joins on mount. Latency
	// honesty (PLAN §3): the status line names what's actually happening —
	// "building," then "running" — rather than a bare spinner, since a ~2s
	// wait that looks like nothing is happening reads as broken.
	import { onDestroy, onMount } from 'svelte';
	import { EditorView, basicSetup } from 'codemirror';
	import { EditorState } from '@codemirror/state';
	import { StreamLanguage } from '@codemirror/language';
	import { swift } from '@codemirror/legacy-modes/mode/swift';
	import { createSession, joinChannel, resetSnippet, runSnippet, writeSnippet } from '$lib/client/session';

	let { initialCode }: { initialCode: string } = $props();

	let editorHost: HTMLDivElement;
	let view: EditorView | undefined;
	let outputLines = $state<{ kind: string; text: string }[]>([]);
	let status = $state<'connecting' | 'idle' | 'saving' | 'building' | 'running' | 'error'>(
		'connecting'
	);
	let statusMessage = $state('');
	let leaveChannel: (() => void) | undefined;

	function appendOutput(kind: string, text: string) {
		if (text.length > 0) outputLines.push({ kind, text });
	}

	function handleRunEvent(event: { event: string; data: string }) {
		switch (event.event) {
			case 'build_output':
				status = 'building';
				appendOutput('build', event.data);
				break;
			case 'build_done':
				if (event.data !== '0') {
					status = 'error';
					appendOutput('error', `build failed (exit ${event.data})`);
				}
				break;
			case 'run_output':
				status = 'running';
				appendOutput('run', event.data);
				break;
			case 'exited':
				status = event.data === '0' ? 'idle' : 'error';
				break;
			case 'timed_out':
				status = 'error';
				appendOutput('error', 'timed out — this runner has a wall-clock limit per run');
				break;
			case 'truncated':
				appendOutput('error', '(output truncated)');
				break;
			case 'channel_error':
				status = 'error';
				statusMessage = 'lost the connection to your session — reloading the page will start a new one';
				break;
			case 'session_expired':
				status = 'error';
				statusMessage = 'your session expired from inactivity — reload the page to get a new one';
				break;
			case 'run_error':
				status = 'error';
				statusMessage = event.data;
				break;
		}
	}

	onMount(() => {
		view = new EditorView({
			state: EditorState.create({
				doc: initialCode,
				extensions: [basicSetup, StreamLanguage.define(swift)]
			}),
			parent: editorHost
		});

		(async () => {
			try {
				const session = await createSession();
				leaveChannel = joinChannel(session.topic, handleRunEvent);
				status = 'idle';
			} catch (error) {
				status = 'error';
				statusMessage = error instanceof Error ? error.message : String(error);
			}
		})();
	});

	onDestroy(() => {
		view?.destroy();
		leaveChannel?.();
	});

	async function run() {
		if (!view) return;
		outputLines = [];
		statusMessage = '';
		status = 'saving';
		try {
			await writeSnippet(view.state.doc.toString());
			await runSnippet();
			// status becomes 'building'/'running' from the channel pushes
			// above — not set here, so a slow build shows real progress
			// rather than a status that jumps straight to "running."
		} catch (error) {
			status = 'error';
			statusMessage = error instanceof Error ? error.message : String(error);
		}
	}

	async function reset() {
		if (!view) return;
		try {
			await resetSnippet();
			view.dispatch({
				changes: { from: 0, to: view.state.doc.length, insert: initialCode }
			});
			outputLines = [];
			statusMessage = '';
			status = 'idle';
		} catch (error) {
			status = 'error';
			statusMessage = error instanceof Error ? error.message : String(error);
		}
	}
</script>

<div class="snippet-editor">
	<div class="toolbar">
		<button onclick={run} disabled={status === 'saving' || status === 'building' || status === 'connecting'}>
			Run
		</button>
		<button onclick={reset} disabled={status === 'connecting'}>Reset</button>
		<span class="status status-{status}">
			{#if status === 'connecting'}
				connecting…
			{:else if status === 'saving'}
				saving…
			{:else if status === 'building'}
				building…
			{:else if status === 'running'}
				running…
			{:else if status === 'error'}
				{statusMessage || 'error'}
			{:else}
				ready
			{/if}
		</span>
	</div>
	<div class="editor" bind:this={editorHost}></div>
	{#if outputLines.length > 0}
		<pre class="output">{#each outputLines as line}<span class="line line-{line.kind}"
					>{line.text}</span
				>
{/each}</pre>
	{/if}
</div>

<style>
	.snippet-editor {
		border: 1px solid var(--line);
		border-radius: 8px;
		overflow: hidden;
		margin: 24px 0;
	}
	.toolbar {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 8px 12px;
		background: var(--line);
	}
	.toolbar button {
		border: 1px solid var(--line);
		background: var(--accent);
		color: var(--accent-ink);
		border-radius: 6px;
		padding: 4px 14px;
		font-size: 0.9rem;
		cursor: pointer;
	}
	.toolbar button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.status {
		font-size: 0.85rem;
		color: var(--muted);
		margin-left: auto;
	}
	.status-error {
		color: #d33;
	}
	.editor {
		font-size: 0.92rem;
	}
	.editor :global(.cm-editor) {
		height: auto;
	}
	.output {
		margin: 0;
		padding: 10px 14px;
		border-top: 1px solid var(--line);
		background: var(--bg);
		font-size: 0.85rem;
		max-height: 320px;
		overflow-y: auto;
		white-space: pre-wrap;
	}
	.line-error {
		color: #d33;
	}
</style>
