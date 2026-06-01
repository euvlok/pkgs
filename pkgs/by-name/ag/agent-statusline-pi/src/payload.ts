import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { positive } from "./format";
import type { State } from "./types";
import { inputUsageForContext, sumUsage } from "./usage";

export function buildPayload(ctx: ExtensionContext, state: State) {
	const entries = ctx.sessionManager.getEntries();
	const usage = sumUsage(entries);
	const context = ctx.getContextUsage();
	const currentUsage = inputUsageForContext(ctx.sessionManager.getBranch(), context);
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
				input_tokens: currentUsage.input,
				output_tokens: usage.output,
				cache_creation_input_tokens: currentUsage.cacheWrite,
				cache_read_input_tokens: currentUsage.cacheRead,
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
