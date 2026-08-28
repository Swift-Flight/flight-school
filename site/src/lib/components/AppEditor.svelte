<script lang="ts">
	// The app tier's editor (PLAN §3/§4, M3): the learner edits one file
	// inside a real Flight project, Run rebuilds and restarts the app on
	// the leased runner, and the Preview tab embeds it through the
	// `/preview/runner-N/` proxy.
	//
	// Shares SnippetEditor's session/channel wiring and latency-honesty
	// posture, but not its shape: this one runs a *server* rather than a
	// program that finishes, so there is no "exited 0" to report as
	// success — the run ends at `server_started` and the app keeps
	// serving. Tabs rather than a stacked output pane, because a preview
	// needs real height.
	//
	// One file, no file tree: no exercise yet has more than one focus
	// path, and a tree with a single leaf is furniture, not navigation.
	import { onDestroy, onMount } from 'svelte';
	import { EditorView, basicSetup } from 'codemirror';
	import { EditorState } from '@codemirror/state';
	import { StreamLanguage } from '@codemirror/language';
	import { swift } from '@codemirror/legacy-modes/mode/swift';
	import { createSession, joinChannel, resetSnippet, runSnippet, writeFiles } from '$lib/client/session';

	let { initialCode, focus }: { initialCode: string; focus: string } = $props();

	let editorHost: HTMLDivElement;
	let view: EditorView | undefined;
	let outputLines = $state<{ kind: string; text: string }[]>([]);
	let status = $state<'connecting' | 'idle' | 'saving' | 'building' | 'serving' | 'error'>(
		'connecting'
	);
	let statusMessage = $state('');
	let tab = $state<'editor' | 'output' | 'preview'>('editor');
	let previewPath = $state<string | undefined>(undefined);
	// Only true once *this* run has reported a live server. Reset on each
	// Run so the preview never shows the previous build's app as though it
	// were the new one.
	let serverLive = $state(false);
	// Cache-busts the iframe so a rebuild actually reloads it rather than
	// showing the previous response from bfcache.
	let previewNonce = $state(0);
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
					tab = 'output';
				}
				break;
			case 'run_output':
				// Before `server_started` this is the app's own startup
				// output — including whatever it printed on the way down if
				// it crashed at boot.
				appendOutput('run', event.data);
				break;
			case 'server_started':
				status = 'serving';
				serverLive = true;
				previewNonce += 1;
				tab = 'preview';
				break;
			case 'exited':
				// The app tier only reports this when the server failed to
				// stay up — a healthy run ends at `server_started` with the
				// process still going.
				status = 'error';
				appendOutput('error', `your app exited (${event.data}) instead of staying up`);
				tab = 'output';
				break;
			case 'timed_out':
				status = 'error';
				appendOutput('error', 'the build hit its time limit');
				tab = 'output';
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
				serverLive = false;
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
				const session = await createSession({ tier: 'app' });
				previewPath = session.previewPath;
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
		serverLive = false;
		status = 'saving';
		tab = 'output';
		try {
			await writeFiles({ [focus]: view.state.doc.toString() });
			await runSnippet();
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
			serverLive = false;
			status = 'idle';
			tab = 'editor';
		} catch (error) {
			status = 'error';
			statusMessage = error instanceof Error ? error.message : String(error);
		}
	}
</script>

<div class="app-editor">
	<div class="toolbar">
		<button onclick={run} disabled={status === 'saving' || status === 'building' || status === 'connecting'}>
			Run
		</button>
		<button onclick={reset} disabled={status === 'connecting'}>Reset</button>
		<div class="tabs" role="tablist">
			<button role="tab" aria-selected={tab === 'editor'} class:active={tab === 'editor'} onclick={() => (tab = 'editor')}>
				Editor
			</button>
			<button role="tab" aria-selected={tab === 'output'} class:active={tab === 'output'} onclick={() => (tab = 'output')}>
				Output
			</button>
			<button role="tab" aria-selected={tab === 'preview'} class:active={tab === 'preview'} onclick={() => (tab = 'preview')}>
				Preview
			</button>
		</div>
		<span class="status status-{status}">
			{#if status === 'connecting'}
				connecting…
			{:else if status === 'saving'}
				saving…
			{:else if status === 'building'}
				building…
			{:else if status === 'serving'}
				serving
			{:else if status === 'error'}
				{statusMessage || 'error'}
			{:else}
				ready
			{/if}
		</span>
	</div>

	<div class="filename">{focus}</div>

	<!-- Kept mounted rather than re-created per tab: CodeMirror owns its
	     own DOM, and tearing it down on every tab switch would lose the
	     learner's cursor, scroll position and undo history. -->
	<div class="pane" class:hidden={tab !== 'editor'}>
		<div class="editor" bind:this={editorHost}></div>
	</div>

	<div class="pane" class:hidden={tab !== 'output'}>
		{#if outputLines.length > 0}
			<pre class="output">{#each outputLines as line}<span class="line line-{line.kind}"
						>{line.text}</span
					>
{/each}</pre>
		{:else}
			<p class="placeholder">Press Run to build and start your app.</p>
		{/if}
	</div>

	<div class="pane" class:hidden={tab !== 'preview'}>
		{#if serverLive && previewPath}
			<!-- The sandbox attribute is not doing isolation work here:
			     allow-scripts plus allow-same-origin on same-origin content
			     effectively disables it. That's acceptable at v1's trust
			     level (no accounts, and the session cookie is HttpOnly), and
			     the real fix is a separate preview origin — PLAN §5's own
			     stated hardening step. It is here to keep top-level
			     navigation and popups out, which it does do. -->
			<iframe
				title="Your running app"
				class="preview"
				sandbox="allow-scripts allow-same-origin allow-forms"
				src="{previewPath}?v={previewNonce}"
			></iframe>
		{:else}
			<p class="placeholder">
				Press Run to start your app — the preview appears once it's serving.
			</p>
		{/if}
	</div>
</div>

<style>
	.app-editor {
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
	.toolbar > button {
		border: 1px solid var(--line);
		background: var(--accent);
		color: var(--accent-ink);
		border-radius: 6px;
		padding: 4px 14px;
		font-size: 0.9rem;
		cursor: pointer;
	}
	.toolbar > button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.tabs {
		display: flex;
		gap: 2px;
		margin-left: 8px;
	}
	.tabs button {
		border: 1px solid transparent;
		background: transparent;
		color: var(--muted);
		border-radius: 6px;
		padding: 4px 12px;
		font-size: 0.85rem;
		cursor: pointer;
	}
	.tabs button.active {
		background: var(--bg);
		color: var(--ink);
		border-color: var(--line);
	}
	.status {
		font-size: 0.85rem;
		color: var(--muted);
		margin-left: auto;
	}
	.status-error {
		color: #d33;
	}
	.filename {
		padding: 6px 14px;
		border-bottom: 1px solid var(--line);
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.8rem;
		color: var(--muted);
	}
	.pane.hidden {
		display: none;
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
		background: var(--bg);
		font-size: 0.85rem;
		max-height: 420px;
		overflow-y: auto;
		white-space: pre-wrap;
	}
	.line-error {
		color: #d33;
	}
	.placeholder {
		margin: 0;
		padding: 24px 14px;
		color: var(--muted);
		font-size: 0.9rem;
	}
	.preview {
		display: block;
		width: 100%;
		height: 420px;
		border: 0;
		background: #fff;
	}
</style>
