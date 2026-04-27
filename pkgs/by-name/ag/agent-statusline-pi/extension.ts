import type { AssistantMessage } from "@mariozechner/pi-ai";
import {
	type ExtensionAPI,
	type ExtensionContext,
	isEditToolResult,
	isWriteToolResult,
	type ToolResultEvent,
} from "@mariozechner/pi-coding-agent";

const FLAG_COMMAND = "statusline-command";
const FLAG_ARGS = "statusline-args";
const STATUS_KEY = "agent-statusline";
const DEFAULT_COMMAND = "agent-statusline";
const REFRESH_DEBOUNCE_MS = 200;
const SPAWN_TIMEOUT_MS = 3000;
const IDLE_TICK_MS = 30_000;
const PI_STATUSLINE_COMMAND = "PI_STATUSLINE_COMMAND";
const PI_STATUSLINE_ARGS = "PI_STATUSLINE_ARGS";

const STATUSLINE_FLAGS = [
	{ name: FLAG_COMMAND, description: `Statusline command to spawn (default: ${DEFAULT_COMMAND})` },
	{ name: FLAG_ARGS, description: "Extra args forwarded to the statusline command (whitespace-separated or JSON string array)" },
] as const;

type DiffStats = { added: number; removed: number };
type AssistantUsage = NonNullable<AssistantMessage["usage"]>;
type State = { headers?: Record<string, string>; diff: DiffStats; apiDurationMs: number };
type SessionEntry = ReturnType<ExtensionContext["sessionManager"]["getEntries"]>[number];
type Statusline = { schedule(force?: boolean): void; dispose(): void };

const zeroDiff = (): DiffStats => ({ added: 0, removed: 0 });
const positive = (n: number) => (n > 0 ? n : undefined);
const hasFormatArg = (args: readonly string[]) => args.some((a) => a === "--format" || a.startsWith("--format="));
const assistantUsage = (entry: SessionEntry) =>
	entry.type === "message" && entry.message.role === "assistant" ? (entry.message as AssistantMessage).usage : undefined;
const oneLine = (text: string) =>
	text
		.replace(/[\r\n\t]/g, " ")
		.replace(/ +/g, " ")
		.trim();

function parseStatuslineArgs(value: string): string[] {
	const input = value.trim();
	if (!input) return [];
	if (!input.startsWith("[")) return input.split(/\s+/).filter(Boolean);

	const parsed: unknown = JSON.parse(input);
	if (!Array.isArray(parsed) || !parsed.every((arg) => typeof arg === "string")) {
		throw new Error("statusline args JSON must be an array of strings");
	}
	return parsed;
}

function diffFromToolResult(event: ToolResultEvent): DiffStats {
	if (event.isError) return zeroDiff();
	if (isEditToolResult(event)) {
		return (event.details?.diff ?? "").split("\n").reduce(
			(acc, line) => ({
				added: acc.added + Number(line.startsWith("+") && !line.startsWith("+++")),
				removed: acc.removed + Number(line.startsWith("-") && !line.startsWith("---")),
			}),
			zeroDiff(),
		);
	}
	if (isWriteToolResult(event) && typeof event.input.content === "string" && event.input.content) {
		const lines = event.input.content.split("\n").length;
		return { added: event.input.content.endsWith("\n") ? lines - 1 : lines, removed: 0 };
	}
	return zeroDiff();
}

function buildPayload(ctx: ExtensionContext, state: State) {
	const usage = ctx.sessionManager
		.getEntries()
		.map(assistantUsage)
		.filter((usage): usage is AssistantUsage => usage !== undefined)
		.reduce(
			(acc, usage) => ({
				input: acc.input + usage.input,
				output: acc.output + usage.output,
				cacheRead: acc.cacheRead + usage.cacheRead,
				cacheWrite: acc.cacheWrite + usage.cacheWrite,
			}),
			{ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		);
	const context = ctx.getContextUsage();
	const header = ctx.sessionManager.getHeader();
	const startedAt = Date.parse(header?.timestamp ?? "");
	return {
		workspace: { current_dir: ctx.cwd },
		cwd: ctx.cwd,
		transcript_path: ctx.sessionManager.getSessionFile(),
		session_id: header?.id ?? ctx.sessionManager.getSessionId(),
		model: { display_name: ctx.model?.name ?? ctx.model?.id ?? "no-model" },
		context_window: {
			used_percentage: context?.percent ?? undefined,
			context_window_size: context?.contextWindow ?? ctx.model?.contextWindow,
			current_usage: {
				input_tokens: usage.input,
				output_tokens: usage.output,
				cache_creation_input_tokens: usage.cacheWrite,
				cache_read_input_tokens: usage.cacheRead,
			},
		},
		cost: {
			total_duration_ms: Number.isFinite(startedAt) ? Math.max(0, Date.now() - startedAt) : undefined,
			total_api_duration_ms: positive(state.apiDurationMs),
			total_lines_added: positive(state.diff.added),
			total_lines_removed: positive(state.diff.removed),
		},
		headers: state.headers,
	};
}

export default function agentStatuslineExtension(pi: ExtensionAPI): void {
	STATUSLINE_FLAGS.forEach((flag) => {
		pi.registerFlag(flag.name, { type: "string", description: flag.description });
	});

	let statusline: Statusline | undefined;
	const state: State = { diff: zeroDiff(), apiDurationMs: 0 };
	let requestStartedAt: number | undefined;
	const schedule = () => statusline?.schedule();

	pi.on("before_provider_request", () => {
		requestStartedAt = Date.now();
	});
	pi.on("after_provider_response", (event) => {
		if (requestStartedAt !== undefined) state.apiDurationMs += Date.now() - requestStartedAt;
		requestStartedAt = undefined;
		if (event.headers && Object.keys(event.headers).length > 0) state.headers = event.headers;
		schedule();
	});
	pi.on("tool_result", (event) => {
		const diff = diffFromToolResult(event);
		if (!diff.added && !diff.removed) return;
		state.diff.added += diff.added;
		state.diff.removed += diff.removed;
		schedule();
	});
	[
		() => pi.on("message_end", schedule),
		() => pi.on("turn_end", schedule),
		() => pi.on("model_select", schedule),
		() => pi.on("input", schedule),
		() => pi.on("user_bash", schedule),
		() => pi.on("session_compact", schedule),
		() => pi.on("session_tree", schedule),
	].forEach((listen) => {
		listen();
	});

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		Object.assign(state, { headers: undefined, diff: zeroDiff(), apiDurationMs: 0 });
		requestStartedAt = undefined;

		let lastRunAt = 0;
		let pending: ReturnType<typeof setTimeout> | undefined;
		let inflight: AbortController | undefined;
		let tick: ReturnType<typeof setInterval> | undefined;
		let runId = 0;

		const flag = (key: string) => {
			const value = pi.getFlag(key);
			return typeof value === "string" ? value : "";
		};

		const refresh = async () => {
			const currentRun = ++runId;
			inflight?.abort();
			inflight = new AbortController();

			const cmd = flag(FLAG_COMMAND) || process.env[PI_STATUSLINE_COMMAND] || DEFAULT_COMMAND;
			try {
				const args = parseStatuslineArgs(flag(FLAG_ARGS) || process.env[PI_STATUSLINE_ARGS] || "");
				const renderArgs = hasFormatArg(args) ? args : [...args, "--format", "text"];
				const result = await pi.exec(cmd, [...renderArgs, "--input-json", JSON.stringify(buildPayload(ctx, state))], {
					signal: inflight.signal,
					timeout: SPAWN_TIMEOUT_MS,
				});
				if (currentRun !== runId) return;

				lastRunAt = Date.now();
				const detail = result.killed ? "timed out" : result.stderr.trim().split("\n")[0];
				ctx.ui.setStatus(
					STATUS_KEY,
					result.code === 0
						? oneLine(result.stdout.replace(/\n+$/, ""))
						: ctx.ui.theme.fg("error", `[statusline] ${cmd} exited ${result.code}${detail ? `: ${detail}` : ""}`),
				);
			} catch (err) {
				if (currentRun !== runId) return;
				lastRunAt = Date.now();
				ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("error", `[statusline] ${err instanceof Error ? err.message : String(err)}`));
			}
		};

		statusline = {
			schedule(force = false) {
				if (pending) {
					if (!force) return;
					clearTimeout(pending);
					pending = undefined;
				}
				const delay = force || lastRunAt === 0 ? 0 : Math.max(0, REFRESH_DEBOUNCE_MS - (Date.now() - lastRunAt));
				pending = setTimeout(() => {
					pending = undefined;
					void refresh();
				}, delay);
			},
			dispose() {
				inflight?.abort();
				if (pending) clearTimeout(pending);
				if (tick) clearInterval(tick);
				ctx.ui.setStatus(STATUS_KEY, undefined);
			},
		};

		tick = setInterval(statusline.schedule, IDLE_TICK_MS);
		tick.unref?.();
		statusline.schedule();
	});

	pi.on("session_shutdown", () => {
		statusline?.dispose();
		statusline = undefined;
		requestStartedAt = undefined;
	});

	pi.registerCommand("statusline-refresh", {
		description: "Force-refresh the agent-statusline status",
		handler: async () => statusline?.schedule(true),
	});
	pi.registerCommand("statusline-default", {
		description: "Clear the agent-statusline status and use pi's built-in footer only",
		handler: async (_args, ctx) => {
			statusline?.dispose();
			statusline = undefined;
			ctx.ui.notify("agent-statusline cleared", "info");
		},
	});
}
