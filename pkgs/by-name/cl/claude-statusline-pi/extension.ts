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

const FLAG_COMMAND = "statusline-command";
const FLAG_ARGS = "statusline-args";
const DEFAULT_COMMAND = "claude-statusline";

const REFRESH_DEBOUNCE_MS = 200;
const SPAWN_TIMEOUT_MS = 3000;
const IDLE_TICK_MS = 30_000;

// Lifecycle events that should trigger a (debounced) re-render of the footer.
const REFRESH_EVENTS = ["message_end", "turn_end", "model_select"] as const;

interface DiffStats {
	added: number;
	removed: number;
}

const ZERO_DIFF: DiffStats = { added: 0, removed: 0 };

// Wire shape consumed by `claude-statusline` (Rust). Mirrors the serde
// structs in `claude-statusline/src/input.rs`; keep in sync by hand.
// `headers` carries raw HTTP response headers; the binary extracts
// Codex-format rate-limit fields (`x-codex-{primary,secondary}-…`) itself.
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

function diffFromToolResult(event: ToolResultEvent): DiffStats {
	if (event.isError) return ZERO_DIFF;
	if (isEditToolResult(event)) {
		const diff = event.details?.diff;
		if (!diff) return ZERO_DIFF;
		const lines = diff.split("\n");
		return {
			added: lines.filter((l) => l.startsWith("+") && !l.startsWith("+++")).length,
			removed: lines.filter((l) => l.startsWith("-") && !l.startsWith("---")).length,
		};
	}
	if (isWriteToolResult(event)) {
		const c = event.input.content;
		if (typeof c !== "string" || c.length === 0) return ZERO_DIFF;
		const n = c.split("\n").length;
		return { added: c.endsWith("\n") ? n - 1 : n, removed: 0 };
	}
	return ZERO_DIFF;
}

function resolveCommand(pi: ExtensionAPI): { cmd: string; args: string[] } {
	const cmdFlag = pi.getFlag(FLAG_COMMAND);
	const argsFlag = pi.getFlag(FLAG_ARGS);
	const cmd = (typeof cmdFlag === "string" && cmdFlag) || process.env.PI_STATUSLINE_COMMAND || DEFAULT_COMMAND;
	const argsStr = (typeof argsFlag === "string" && argsFlag) || process.env.PI_STATUSLINE_ARGS || "";
	return { cmd, args: argsStr.split(/\s+/).filter(Boolean) };
}

// Walk the active branch (not all entries) so usage doesn't double-count
// abandoned messages after a rewind.
function buildPayload(ctx: ExtensionContext, sessionStartedAtMs: number, state: StatuslineState): StatuslinePayload {
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
			total_duration_ms: Math.max(0, Date.now() - sessionStartedAtMs),
			total_api_duration_ms: state.apiDurationMs > 0 ? state.apiDurationMs : undefined,
			total_lines_added: state.diff.added > 0 ? state.diff.added : undefined,
			total_lines_removed: state.diff.removed > 0 ? state.diff.removed : undefined,
		},
		headers: state.headers,
	};
}

// One instance per `session_start`; replaced on session change. Caches the
// most recent statusline output and debounces subprocess runs.
class StatuslineFooter implements Component {
	private cachedLines: string[] = [];
	private lastError: string | undefined;
	private lastRunAt = 0;
	private pending: ReturnType<typeof setTimeout> | undefined;
	private inflight: AbortController | undefined;
	private readonly tickInterval: ReturnType<typeof setInterval>;
	private readonly unsubBranch: () => void;

	constructor(
		private readonly pi: ExtensionAPI,
		private readonly ctx: ExtensionContext,
		private readonly tui: TUI,
		private readonly theme: Theme,
		private readonly footerData: ReadonlyFooterDataProvider,
		private readonly sessionStartedAtMs: number,
		private readonly state: StatuslineState,
	) {
		this.unsubBranch = footerData.onBranchChange(() => this.schedule());
		this.tickInterval = setInterval(() => this.schedule(), IDLE_TICK_MS);
		this.tickInterval.unref?.();
		this.schedule();
	}

	schedule(): void {
		if (this.pending) return;
		const since = Date.now() - this.lastRunAt;
		const delay = this.lastRunAt === 0 ? 0 : Math.max(0, REFRESH_DEBOUNCE_MS - since);
		this.pending = setTimeout(() => {
			this.pending = undefined;
			void this.refresh();
		}, delay);
	}

	render(width: number): string[] {
		const ellipsis = this.theme.fg("dim", "...");
		const lines =
			this.cachedLines.length > 0
				? this.cachedLines.map((l) => truncateToWidth(l, width, ellipsis))
				: [this.lastError ? this.theme.fg("error", `[statusline] ${this.lastError}`) : ""];

		const exts = this.footerData.getExtensionStatuses();
		if (exts.size > 0) {
			const status = Array.from(exts.entries())
				.sort(([a], [b]) => a.localeCompare(b))
				.map(([, value]) => value)
				.join(" ");
			lines.push(truncateToWidth(status, width, ellipsis));
		}
		return lines;
	}

	invalidate(): void {}

	dispose(): void {
		this.inflight?.abort();
		if (this.pending) clearTimeout(this.pending);
		clearInterval(this.tickInterval);
		this.unsubBranch();
	}

	private async refresh(): Promise<void> {
		this.inflight?.abort();
		this.inflight = new AbortController();

		const payload = buildPayload(this.ctx, this.sessionStartedAtMs, this.state);
		const { cmd, args } = resolveCommand(this.pi);
		const result = await this.pi.exec(cmd, [...args, "--input-json", JSON.stringify(payload)], {
			signal: this.inflight.signal,
			timeout: SPAWN_TIMEOUT_MS,
		});

		this.lastRunAt = Date.now();
		if (result.code === 0) {
			this.lastError = undefined;
			this.cachedLines = result.stdout.replace(/\n+$/, "").split("\n").filter(Boolean);
		} else {
			this.lastError = `${cmd} exited ${result.code}`;
			this.cachedLines = [];
		}
		this.tui.requestRender();
	}
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

	let activeFooter: StatuslineFooter | undefined;
	const state: StatuslineState = { headers: undefined, diff: { ...ZERO_DIFF }, apiDurationMs: 0 };
	let requestStartedAt: number | undefined;

	pi.on("before_provider_request", () => {
		requestStartedAt = Date.now();
	});

	pi.on("after_provider_response", (event) => {
		if (requestStartedAt !== undefined) {
			state.apiDurationMs += Date.now() - requestStartedAt;
			requestStartedAt = undefined;
		}
		// Forward raw headers; the binary extracts Codex rate-limit fields.
		// Only replace when the response actually carried headers, so a
		// header-less response can't clobber the cache.
		if (event.headers && Object.keys(event.headers).length > 0) state.headers = event.headers;
		activeFooter?.schedule();
	});

	pi.on("tool_result", (event) => {
		const d = diffFromToolResult(event);
		if (d.added === 0 && d.removed === 0) return;
		state.diff = { added: state.diff.added + d.added, removed: state.diff.removed + d.removed };
		activeFooter?.schedule();
	});

	for (const ev of REFRESH_EVENTS) pi.on(ev, () => activeFooter?.schedule());

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		state.diff = { ...ZERO_DIFF };
		state.apiDurationMs = 0;
		state.headers = undefined;
		requestStartedAt = undefined;
		const sessionStartedAtMs = Date.now();
		ctx.ui.setFooter((tui, theme, footerData) => {
			activeFooter = new StatuslineFooter(pi, ctx, tui, theme, footerData, sessionStartedAtMs, state);
			return activeFooter;
		});
	});

	pi.on("session_shutdown", () => {
		activeFooter = undefined;
	});

	pi.registerCommand("statusline-refresh", {
		description: "Force-refresh the claude-statusline footer",
		handler: async () => {
			activeFooter?.schedule();
		},
	});

	pi.registerCommand("statusline-default", {
		description: "Restore pi-mono's built-in footer",
		handler: async (_args, ctx) => {
			ctx.ui.setFooter(undefined);
			ctx.ui.notify("Built-in footer restored", "info");
		},
	});
}
