import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
	DEFAULT_COMMAND,
	FLAG_ARGS,
	FLAG_COMMAND,
	IDLE_TICK_MS,
	PI_STATUSLINE_ARGS,
	PI_STATUSLINE_COMMAND,
	REFRESH_DEBOUNCE_MS,
	SPAWN_TIMEOUT_MS,
	STATUS_KEY,
} from "./constants";
import { hasFormatArg, oneLine, parseStatuslineArgs } from "./format";
import { buildPayload } from "./payload";
import type { State, Statusline } from "./types";

export function createStatusline(pi: ExtensionAPI, ctx: ExtensionContext, state: State): Statusline {
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

	const statusline: Statusline = {
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
	return statusline;
}
