/**
 * Renders `claude-statusline` as pi-mono's interactive footer.
 *
 * Builds a Claude-Code-shaped JSON payload from the active session, runs
 * the configured statusline command with `--input-json`, and installs the
 * rendered ANSI block via `ctx.ui.setFooter`. Refreshes (debounced) on
 * lifecycle events, git branch changes, and an idle tick.
 *
 * Configure via `--statusline-command` / `--statusline-args` flags, or
 * `PI_STATUSLINE_COMMAND` / `PI_STATUSLINE_ARGS` env vars.
 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import {
	type ExtensionAPI,
	type ExtensionContext,
	isEditToolResult,
	isWriteToolResult,
	type ReadonlyFooterDataProvider,
	type Theme,
	type ToolResultEvent,
} from "@mariozechner/pi-coding-agent";
import { type Component, truncateToWidth, type TUI } from "@mariozechner/pi-tui";

type FooterComponent = Component & { schedule(): void; dispose(): void };

const FLAG_COMMAND = "statusline-command";
const FLAG_ARGS = "statusline-args";
const DEFAULT_COMMAND = "claude-statusline";
const REFRESH_DEBOUNCE_MS = 200;
const SPAWN_TIMEOUT_MS = 3000;
const IDLE_TICK_MS = 30_000;

type DiffStats = { added: number; removed: number };

// Wire shape consumed by `claude-statusline` (Rust). Mirrors the serde structs
// in `claude-statusline/src/input.rs`; keep in sync by hand. `headers` carries
// raw HTTP response headers; the binary extracts Codex-format rate-limit fields.
interface StatuslinePayload {
	workspace: { current_dir: string };
	model: { display_name: string };
	context_window: {
		used_percentage?: number;
		context_window_size?: number;
		current_usage: {
			input_tokens: number;
			output_tokens: number;
			cache_creation_input_tokens: number;
			cache_read_input_tokens: number;
		};
	};
	cost: {
		total_duration_ms?: number;
		total_api_duration_ms?: number;
		total_lines_added?: number;
		total_lines_removed?: number;
	};
	headers?: Record<string, string>;
}

interface StatuslineState {
	headers: Record<string, string> | undefined;
	diff: DiffStats;
	apiDurationMs: number;
}

const zeroDiff = (): DiffStats => ({ added: 0, removed: 0 });
const orUndef = (n: number) => (n > 0 ? n : undefined);

function diffFromToolResult(event: ToolResultEvent): DiffStats {
	if (event.isError) return zeroDiff();
	if (isEditToolResult(event)) {
		const lines = event.details?.diff?.split("\n") ?? [];
		return {
			added: lines.filter((l) => l.startsWith("+") && !l.startsWith("+++")).length,
			removed: lines.filter((l) => l.startsWith("-") && !l.startsWith("---")).length,
		};
	}
	if (isWriteToolResult(event)) {
		const c = event.input.content;
		if (typeof c !== "string" || !c) return zeroDiff();
		const n = c.split("\n").length;
		return { added: c.endsWith("\n") ? n - 1 : n, removed: 0 };
	}
	return zeroDiff();
}

// Walk the active branch (not all entries) so usage doesn't double-count
// abandoned messages after a rewind.
function buildPayload(ctx: ExtensionContext, state: StatuslineState): StatuslinePayload {
	const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
	for (const entry of ctx.sessionManager.getBranch()) {
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const u = (entry.message as AssistantMessage).usage;
		usage.input += u.input;
		usage.output += u.output;
		usage.cacheRead += u.cacheRead;
		usage.cacheWrite += u.cacheWrite;
	}
	const ctxUsage = ctx.getContextUsage();
	const startedAt = Date.parse(ctx.sessionManager.getHeader()?.timestamp ?? "");
	return {
		workspace: { current_dir: ctx.sessionManager.getCwd() },
		model: { display_name: ctx.model?.name ?? ctx.model?.id ?? "no-model" },
		context_window: {
			used_percentage: ctxUsage?.percent ?? undefined,
			context_window_size: ctxUsage?.contextWindow,
			current_usage: {
				input_tokens: usage.input,
				output_tokens: usage.output,
				cache_creation_input_tokens: usage.cacheWrite,
				cache_read_input_tokens: usage.cacheRead,
			},
		},
		cost: {
			total_duration_ms: Number.isFinite(startedAt) ? Math.max(0, Date.now() - startedAt) : undefined,
			total_api_duration_ms: orUndef(state.apiDurationMs),
			total_lines_added: orUndef(state.diff.added),
			total_lines_removed: orUndef(state.diff.removed),
		},
		headers: state.headers,
	};
}

// Built fresh per `session_start`; replaced on session change. Caches the
// most recent statusline output and debounces subprocess runs.
function createStatuslineFooter(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	tui: TUI,
	theme: Theme,
	footerData: ReadonlyFooterDataProvider,
	state: StatuslineState,
): FooterComponent {
	let cachedLines: string[] = [];
	let lastError: string | undefined;
	let lastRunAt = 0;
	let pending: ReturnType<typeof setTimeout> | undefined;
	let inflight: AbortController | undefined;

	const flag = (k: string): string => {
		const v = pi.getFlag(k);
		return typeof v === "string" ? v : "";
	};

	const refresh = async (): Promise<void> => {
		inflight?.abort();
		inflight = new AbortController();
		const cmd = flag(FLAG_COMMAND) || process.env.PI_STATUSLINE_COMMAND || DEFAULT_COMMAND;
		const args = (flag(FLAG_ARGS) || process.env.PI_STATUSLINE_ARGS || "").split(/\s+/).filter(Boolean);
		const payload = buildPayload(ctx, state);
		const result = await pi.exec(cmd, [...args, "--input-json", JSON.stringify(payload)], {
			signal: inflight.signal,
			timeout: SPAWN_TIMEOUT_MS,
		});
		lastRunAt = Date.now();
		if (result.code === 0) {
			lastError = undefined;
			cachedLines = result.stdout.replace(/\n+$/, "").split("\n").filter(Boolean);
		} else {
			lastError = `${cmd} exited ${result.code}`;
			cachedLines = [];
		}
		tui.requestRender();
	};

	const schedule = (): void => {
		if (pending) return;
		const delay = lastRunAt === 0 ? 0 : Math.max(0, REFRESH_DEBOUNCE_MS - (Date.now() - lastRunAt));
		pending = setTimeout(() => {
			pending = undefined;
			void refresh();
		}, delay);
	};

	const unsubBranch = footerData.onBranchChange(schedule);
	const tickInterval = setInterval(schedule, IDLE_TICK_MS);
	tickInterval.unref?.();
	schedule();

	return {
		schedule,
		invalidate() {},
		render(width: number): string[] {
			const ellipsis = theme.fg("dim", "...");
			const lines = cachedLines.length > 0
				? cachedLines.map((l) => truncateToWidth(l, width, ellipsis))
				: [lastError ? theme.fg("error", `[statusline] ${lastError}`) : ""];
			const exts = footerData.getExtensionStatuses();
			if (exts.size > 0) {
				const status = [...exts].sort(([a], [b]) => a.localeCompare(b)).map(([, v]) => v).join(" ");
				lines.push(truncateToWidth(status, width, ellipsis));
			}
			return lines;
		},
		dispose() {
			inflight?.abort();
			if (pending) clearTimeout(pending);
			clearInterval(tickInterval);
			unsubBranch();
		},
	};
}

export default function claudeStatuslineExtension(pi: ExtensionAPI): void {
	pi.registerFlag(FLAG_COMMAND, {
		type: "string",
		description: `Statusline command to spawn (default: ${DEFAULT_COMMAND})`,
	});
	pi.registerFlag(FLAG_ARGS, {
		type: "string",
		description: "Extra args (space-separated) forwarded to the statusline command",
	});

	let activeFooter: FooterComponent | undefined;
	const state: StatuslineState = { headers: undefined, diff: zeroDiff(), apiDurationMs: 0 };
	let requestStartedAt: number | undefined;
	const reschedule = (): void => activeFooter?.schedule();

	pi.on("before_provider_request", () => {
		requestStartedAt = Date.now();
	});
	pi.on("after_provider_response", (event) => {
		if (requestStartedAt !== undefined) {
			state.apiDurationMs += Date.now() - requestStartedAt;
			requestStartedAt = undefined;
		}
		// Only replace headers when the response actually carried them, so a
		// header-less response can't clobber the cache.
		if (event.headers && Object.keys(event.headers).length > 0) state.headers = event.headers;
		reschedule();
	});
	pi.on("tool_result", (event) => {
		const d = diffFromToolResult(event);
		if (!d.added && !d.removed) return;
		state.diff.added += d.added;
		state.diff.removed += d.removed;
		reschedule();
	});
	pi.on("message_end", reschedule);
	pi.on("turn_end", reschedule);
	pi.on("model_select", reschedule);

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		state.diff = zeroDiff();
		state.apiDurationMs = 0;
		state.headers = undefined;
		requestStartedAt = undefined;
		ctx.ui.setFooter((tui, theme, footerData) => {
			activeFooter = createStatuslineFooter(pi, ctx, tui, theme, footerData, state);
			return activeFooter;
		});
	});
	pi.on("session_shutdown", () => {
		activeFooter = undefined;
	});

	pi.registerCommand("statusline-refresh", {
		description: "Force-refresh the claude-statusline footer",
		handler: async () => activeFooter?.schedule(),
	});
	pi.registerCommand("statusline-default", {
		description: "Restore pi-mono's built-in footer",
		handler: async (_args, ctx) => {
			ctx.ui.setFooter(undefined);
			ctx.ui.notify("Built-in footer restored", "info");
		},
	});
}
