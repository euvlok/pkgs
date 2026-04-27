import type { AssistantMessage } from "@mariozechner/pi-ai";
import {
	type ExtensionAPI,
	type ExtensionContext,
	isEditToolResult,
	isWriteToolResult,
	type ToolResultEvent,
} from "@mariozechner/pi-coding-agent";
import { type Component, truncateToWidth } from "@mariozechner/pi-tui";

const FLAG_COMMAND = "statusline-command";
const FLAG_ARGS = "statusline-args";
const DEFAULT_COMMAND = "claude-statusline";
const REFRESH_DEBOUNCE_MS = 200;
const SPAWN_TIMEOUT_MS = 3000;
const IDLE_TICK_MS = 30_000;

type DiffStats = { added: number; removed: number };
type Footer = Component & { schedule(): void; dispose(): void };
type State = { headers?: Record<string, string>; diff: DiffStats; apiDurationMs: number };

const zeroDiff = (): DiffStats => ({ added: 0, removed: 0 });
const positive = (n: number) => (n > 0 ? n : undefined);
const hasFormatArg = (args: readonly string[]) => args.some((a) => a === "--format" || a.startsWith("--format="));

function diffFromToolResult(event: ToolResultEvent): DiffStats {
	if (event.isError) return zeroDiff();
	if (isEditToolResult(event)) {
		return (event.details?.diff ?? "").split("\n").reduce(
			(acc, line) => {
				if (line.startsWith("+") && !line.startsWith("+++")) acc.added++;
				if (line.startsWith("-") && !line.startsWith("---")) acc.removed++;
				return acc;
			},
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
	const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
	for (const entry of ctx.sessionManager.getBranch()) {
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const { usage: u } = entry.message as AssistantMessage;
		usage.input += u.input;
		usage.output += u.output;
		usage.cacheRead += u.cacheRead;
		usage.cacheWrite += u.cacheWrite;
	}

	const context = ctx.getContextUsage();
	const startedAt = Date.parse(ctx.sessionManager.getHeader()?.timestamp ?? "");
	return {
		workspace: { current_dir: ctx.cwd },
		model: { display_name: ctx.model?.name ?? ctx.model?.id ?? "no-model" },
		context_window: {
			used_percentage: context?.percent ?? undefined,
			context_window_size: context?.contextWindow,
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

export default function claudeStatuslineExtension(pi: ExtensionAPI): void {
	pi.registerFlag(FLAG_COMMAND, {
		type: "string",
		description: `Statusline command to spawn (default: ${DEFAULT_COMMAND})`,
	});
	pi.registerFlag(FLAG_ARGS, {
		type: "string",
		description: "Extra args (space-separated) forwarded to the statusline command",
	});

	let footer: Footer | undefined;
	const state: State = { diff: zeroDiff(), apiDurationMs: 0 };
	let requestStartedAt: number | undefined;
	const schedule = () => footer?.schedule();

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
	pi.on("message_end", schedule);
	pi.on("turn_end", schedule);
	pi.on("model_select", schedule);

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		Object.assign(state, { headers: undefined, diff: zeroDiff(), apiDurationMs: 0 });
		requestStartedAt = undefined;

		ctx.ui.setFooter((tui, theme, footerData) => {
			let cachedLines: string[] = [];
			let error: string | undefined;
			let lastRunAt = 0;
			let pending: ReturnType<typeof setTimeout> | undefined;
			let inflight: AbortController | undefined;
			let unsubBranch = () => {};
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

				const cmd = flag(FLAG_COMMAND) || process.env.PI_STATUSLINE_COMMAND || DEFAULT_COMMAND;
				const args = (flag(FLAG_ARGS) || process.env.PI_STATUSLINE_ARGS || "").split(/\s+/).filter(Boolean);
				const renderArgs = hasFormatArg(args) ? args : [...args, "--format", "text"];
				const result = await pi.exec(cmd, [...renderArgs, "--input-json", JSON.stringify(buildPayload(ctx, state))], {
					signal: inflight.signal,
					timeout: SPAWN_TIMEOUT_MS,
				});
				if (currentRun !== runId) return;

				lastRunAt = Date.now();
				error = result.code === 0 ? undefined : `${cmd} exited ${result.code}`;
				cachedLines = result.code === 0 ? result.stdout.replace(/\n+$/, "").split("\n").filter(Boolean) : [];
				tui.requestRender();
			};

			const component: Footer = {
				schedule() {
					if (pending) return;
					const delay = lastRunAt === 0 ? 0 : Math.max(0, REFRESH_DEBOUNCE_MS - (Date.now() - lastRunAt));
					pending = setTimeout(() => {
						pending = undefined;
						void refresh();
					}, delay);
				},
				invalidate() {},
				render(width: number): string[] {
					const ellipsis = theme.fg("dim", "...");
					const lines = (cachedLines.length ? cachedLines : [error ? theme.fg("error", `[statusline] ${error}`) : ""])
						.map((line) => truncateToWidth(line, width, ellipsis));
					const statuses = [...footerData.getExtensionStatuses()]
						.sort(([a], [b]) => a.localeCompare(b))
						.map(([, text]) => text)
						.join(" ");
					if (statuses) lines.push(truncateToWidth(statuses, width, ellipsis));
					return lines;
				},
				dispose() {
					inflight?.abort();
					if (pending) clearTimeout(pending);
					if (tick) clearInterval(tick);
					unsubBranch();
				},
			};

			footer = component;
			unsubBranch = footerData.onBranchChange(component.schedule);
			tick = setInterval(component.schedule, IDLE_TICK_MS);
			tick.unref?.();
			component.schedule();
			return component;
		});
	});

	pi.on("session_shutdown", () => {
		footer = undefined;
	});

	pi.registerCommand("statusline-refresh", {
		description: "Force-refresh the claude-statusline footer",
		handler: async () => footer?.schedule(),
	});
	pi.registerCommand("statusline-default", {
		description: "Restore pi-mono's built-in footer",
		handler: async (_args, ctx) => {
			ctx.ui.setFooter(undefined);
			ctx.ui.notify("Built-in footer restored", "info");
		},
	});
}
