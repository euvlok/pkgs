/**
 * Renders `claude-statusline` as pi-mono's interactive footer.
 *
 * Builds a Claude-Code-shaped JSON payload from the active session, pipes it
 * to the configured statusline command, and installs the rendered ANSI block
 * via `ctx.ui.setFooter`. Refreshes (debounced) on lifecycle events, git
 * branch changes, and an idle tick.
 *
 * Configure via `--statusline-command` / `--statusline-args` flags, or
 * `PI_STATUSLINE_COMMAND` / `PI_STATUSLINE_ARGS` env vars.
 */

import { spawn } from "node:child_process";
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
const ENV_COMMAND = "PI_STATUSLINE_COMMAND";
const ENV_ARGS = "PI_STATUSLINE_ARGS";
const DEFAULT_COMMAND = "claude-statusline";

const REFRESH_DEBOUNCE_MS = 200;
const SPAWN_TIMEOUT_MS = 3000;
const IDLE_TICK_MS = 30_000;

interface RateLimitWindow {
	used_percentage?: number;
	resets_at?: number;
}

interface RateLimitSnapshot {
	five_hour: RateLimitWindow;
	seven_day: RateLimitWindow;
}

interface DiffStats {
	added: number;
	removed: number;
}

// Wire shape consumed by `claude-statusline` (Rust). Mirrors the serde
// structs in `claude-statusline/src/input.rs`; keep in sync by hand.
interface StatuslinePayload {
	workspace: { current_dir: string };
	transcript_path?: string;
	session_id?: string;
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
		total_cost_usd: number;
		total_duration_ms?: number;
		total_lines_added?: number;
		total_lines_removed?: number;
	};
	rate_limits?: RateLimitSnapshot;
}

interface UsageTotals {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
}

interface StatuslineState {
	rateLimits: RateLimitSnapshot | undefined;
	diffStats: DiffStats;
}

function readNumberHeader(
	headers: Record<string, string>,
	name: string,
	parser: (value: string) => number,
): number | undefined {
	const raw = headers[name] ?? headers[name.toLowerCase()];
	if (raw === undefined) return undefined;
	const parsed = parser(raw);
	return Number.isFinite(parsed) ? parsed : undefined;
}

// Returns undefined when no rate-limit headers are present, so a cached
// snapshot from a prior response isn't clobbered by an unrelated request.
function parseRateLimitHeaders(headers: Record<string, string>): RateLimitSnapshot | undefined {
	const primaryPct = readNumberHeader(headers, "x-codex-primary-used-percent", Number.parseFloat);
	const secondaryPct = readNumberHeader(headers, "x-codex-secondary-used-percent", Number.parseFloat);
	const primaryReset = readNumberHeader(headers, "x-codex-primary-reset-at", (s) => Number.parseInt(s, 10));
	const secondaryReset = readNumberHeader(headers, "x-codex-secondary-reset-at", (s) => Number.parseInt(s, 10));

	if (primaryPct === undefined && secondaryPct === undefined && primaryReset === undefined && secondaryReset === undefined) {
		return undefined;
	}

	return {
		five_hour: { used_percentage: primaryPct, resets_at: primaryReset },
		seven_day: { used_percentage: secondaryPct, resets_at: secondaryReset },
	};
}

function countDiffStats(diff: string): DiffStats {
	let added = 0;
	let removed = 0;
	for (const line of diff.split("\n")) {
		if (line.startsWith("+++") || line.startsWith("---")) continue;
		if (line.startsWith("+")) added++;
		else if (line.startsWith("-")) removed++;
	}
	return { added, removed };
}

// Approximate added lines from a write: count newlines in the new content.
// `event.input` is loosely typed as Record<string, unknown> for tool results,
// so the runtime guard here is load-bearing, not paranoia.
function countWriteAdditions(content: unknown): number {
	if (typeof content !== "string" || content.length === 0) return 0;
	const lines = content.split("\n").length;
	return content.endsWith("\n") ? lines - 1 : lines;
}

function diffStatsFromToolResult(event: ToolResultEvent): DiffStats {
	if (event.isError) return { added: 0, removed: 0 };
	if (isEditToolResult(event)) {
		const diff = event.details?.diff;
		return diff ? countDiffStats(diff) : { added: 0, removed: 0 };
	}
	if (isWriteToolResult(event)) {
		return { added: countWriteAdditions(event.input.content), removed: 0 };
	}
	return { added: 0, removed: 0 };
}

function resolveCommand(pi: ExtensionAPI): { cmd: string; args: string[] } {
	const cmdFlag = pi.getFlag(FLAG_COMMAND);
	const argsFlag = pi.getFlag(FLAG_ARGS);
	const cmd = (typeof cmdFlag === "string" && cmdFlag) || process.env[ENV_COMMAND] || DEFAULT_COMMAND;
	const argsStr = (typeof argsFlag === "string" && argsFlag) || process.env[ENV_ARGS] || "";
	const args = argsStr.length > 0 ? argsStr.split(/\s+/).filter(Boolean) : [];
	return { cmd, args };
}

// Walk the active branch (not all entries) so usage doesn't double-count
// abandoned messages after a rewind.
function sumAssistantUsage(ctx: ExtensionContext): UsageTotals {
	const totals: UsageTotals = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0 };
	for (const entry of ctx.sessionManager.getBranch()) {
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const { usage } = entry.message as AssistantMessage;
		totals.input += usage.input;
		totals.output += usage.output;
		totals.cacheRead += usage.cacheRead;
		totals.cacheWrite += usage.cacheWrite;
		totals.cost += usage.cost.total;
	}
	return totals;
}

function buildPayload(
	ctx: ExtensionContext,
	sessionStartedAtMs: number,
	rateLimits: RateLimitSnapshot | undefined,
	diff: DiffStats,
): StatuslinePayload {
	const usage = sumAssistantUsage(ctx);
	const contextUsage = ctx.getContextUsage();
	const modelName = ctx.model?.name ?? ctx.model?.id ?? "no-model";

	// session_id + transcript_path give the Rust binary a stable key for
	// its delta-flash tracker (see `session::session_key`). Without them
	// the "since last render" delta segment is suppressed.
	const sessionId = ctx.sessionManager.getSessionId();
	const transcriptPath = ctx.sessionManager.getSessionFile();

	return {
		workspace: { current_dir: ctx.cwd },
		transcript_path: transcriptPath,
		session_id: sessionId.length > 0 ? sessionId : undefined,
		model: { display_name: modelName },
		context_window: {
			used_percentage: contextUsage?.percent ?? undefined,
			context_window_size: contextUsage?.contextWindow,
			current_usage: {
				input_tokens: usage.input,
				output_tokens: usage.output,
				cache_creation_input_tokens: usage.cacheWrite,
				cache_read_input_tokens: usage.cacheRead,
			},
		},
		cost: {
			total_cost_usd: usage.cost,
			total_duration_ms: Math.max(0, Date.now() - sessionStartedAtMs),
			total_lines_added: diff.added > 0 ? diff.added : undefined,
			total_lines_removed: diff.removed > 0 ? diff.removed : undefined,
		},
		rate_limits: rateLimits,
	};
}

// Returns stdout on a clean zero-exit, or null for any failure (spawn error,
// non-zero exit, timeout, abort). Never throws; failure surfaces as null.
function runStatuslineCommand(
	cmd: string,
	args: string[],
	payload: StatuslinePayload,
	signal: AbortSignal,
): Promise<string | null> {
	return new Promise((resolve) => {
		let proc: ReturnType<typeof spawn>;
		try {
			proc = spawn(cmd, args, { stdio: ["pipe", "pipe", "pipe"], shell: false });
		} catch {
			resolve(null);
			return;
		}

		let stdout = "";
		let settled = false;
		const finish = (value: string | null): void => {
			if (settled) return;
			settled = true;
			resolve(value);
		};

		const timer = setTimeout(() => {
			proc.kill("SIGTERM");
			finish(null);
		}, SPAWN_TIMEOUT_MS);

		const onAbort = (): void => {
			proc.kill("SIGTERM");
		};
		if (signal.aborted) {
			proc.kill("SIGTERM");
			finish(null);
		} else {
			signal.addEventListener("abort", onAbort, { once: true });
		}

		proc.stdout?.setEncoding("utf8");
		proc.stdout?.on("data", (chunk: string) => {
			stdout += chunk;
		});
		// Drain stderr so the child doesn't back-pressure on a full pipe.
		proc.stderr?.resume();
		proc.on("error", () => {
			clearTimeout(timer);
			signal.removeEventListener("abort", onAbort);
			finish(null);
		});
		proc.on("close", (code) => {
			clearTimeout(timer);
			signal.removeEventListener("abort", onAbort);
			finish(code === 0 ? stdout : null);
		});

		// Ignore EPIPE if the child exits before reading stdin.
		proc.stdin?.on("error", () => {});
		proc.stdin?.end(JSON.stringify(payload));
	});
}

function splitOutput(out: string): string[] {
	const trimmed = out.replace(/\n+$/, "");
	return trimmed.length > 0 ? trimmed.split("\n") : [];
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
		private readonly readState: () => StatuslineState,
	) {
		this.unsubBranch = this.footerData.onBranchChange(() => this.schedule());
		this.tickInterval = setInterval(() => this.schedule(), IDLE_TICK_MS);
		// Don't block process exit on the idle timer.
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
				? this.cachedLines.map((line) => truncateToWidth(line, width, ellipsis))
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
		if (this.pending) {
			clearTimeout(this.pending);
			this.pending = undefined;
		}
		clearInterval(this.tickInterval);
		this.unsubBranch();
	}

	private async refresh(): Promise<void> {
		this.inflight?.abort();
		this.inflight = new AbortController();

		const { rateLimits, diffStats } = this.readState();
		let payload: StatuslinePayload;
		try {
			payload = buildPayload(this.ctx, this.sessionStartedAtMs, rateLimits, diffStats);
		} catch {
			return;
		}

		const { cmd, args } = resolveCommand(this.pi);
		const out = await runStatuslineCommand(cmd, args, payload, this.inflight.signal);
		this.lastRunAt = Date.now();
		if (out === null) {
			this.lastError = `${cmd} failed`;
			this.cachedLines = [];
		} else {
			this.lastError = undefined;
			this.cachedLines = splitOutput(out);
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
	let rateLimits: RateLimitSnapshot | undefined;
	let diffStats: DiffStats = { added: 0, removed: 0 };
	const readState = (): StatuslineState => ({ rateLimits, diffStats });

	pi.on("after_provider_response", (event) => {
		const snapshot = parseRateLimitHeaders(event.headers ?? {});
		if (!snapshot) return;
		rateLimits = snapshot;
		activeFooter?.schedule();
	});

	pi.on("tool_result", (event) => {
		const stats = diffStatsFromToolResult(event);
		if (stats.added === 0 && stats.removed === 0) return;
		diffStats = { added: diffStats.added + stats.added, removed: diffStats.removed + stats.removed };
		activeFooter?.schedule();
	});

	pi.on("message_end", () => activeFooter?.schedule());
	pi.on("turn_end", () => activeFooter?.schedule());
	pi.on("model_select", () => activeFooter?.schedule());

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		diffStats = { added: 0, removed: 0 };
		const sessionStartedAtMs = Date.now();
		ctx.ui.setFooter((tui, theme, footerData) => {
			activeFooter = new StatuslineFooter(pi, ctx, tui, theme, footerData, sessionStartedAtMs, readState);
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
