import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { STATUSLINE_FLAGS } from "./src/constants";
import { diffFromToolResult, zeroDiff } from "./src/diff";
import { createStatusline } from "./src/statusline";
import type { State, Statusline } from "./src/types";

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
		statusline?.dispose();
		statusline = undefined;
		if (!ctx.hasUI) return;
		Object.assign(state, { headers: undefined, diff: zeroDiff(), apiDurationMs: 0 });
		requestStartedAt = undefined;
		statusline = createStatusline(pi, ctx, state);
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
		description: "Clear the agent-statusline status",
		handler: async (_args, ctx) => {
			statusline?.dispose();
			statusline = undefined;
			ctx.ui.notify("agent-statusline cleared", "info");
		},
	});
}
