import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { AssistantUsage, ContextUsage, SessionEntry, TokenUsage } from "./types";

export const assistantMessage = (entry: SessionEntry) =>
	entry.type === "message" && entry.message.role === "assistant" ? (entry.message as AssistantMessage) : undefined;

const assistantUsage = (entry: SessionEntry) => assistantMessage(entry)?.usage;

export function sumUsage(entries: readonly SessionEntry[]): TokenUsage {
	return entries
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
}

function branchAfterLatestCompaction(entries: readonly SessionEntry[]): readonly SessionEntry[] {
	const index = entries.findLastIndex((entry) => entry.type === "compaction");
	return index === -1 ? entries : entries.slice(index + 1);
}

function lastSuccessfulAssistantUsage(entries: readonly SessionEntry[]): AssistantUsage | undefined {
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i];
		if (!entry) continue;
		const message = assistantMessage(entry);
		if (message && message.stopReason !== "aborted" && message.stopReason !== "error") return message.usage;
	}
	return undefined;
}

export function inputUsageForContext(branchEntries: readonly SessionEntry[], context: ContextUsage | undefined): TokenUsage {
	const contextTokens = typeof context?.tokens === "number" && Number.isFinite(context.tokens) ? Math.max(0, context.tokens) : undefined;
	const lastUsage = lastSuccessfulAssistantUsage(branchAfterLatestCompaction(branchEntries));
	if (!lastUsage) return { input: contextTokens ?? 0, output: 0, cacheRead: 0, cacheWrite: 0 };

	const inputSide = lastUsage.input + lastUsage.cacheRead + lastUsage.cacheWrite;
	if (contextTokens === undefined || inputSide <= 0) {
		return {
			input: lastUsage.input,
			output: lastUsage.output,
			cacheRead: lastUsage.cacheRead,
			cacheWrite: lastUsage.cacheWrite,
		};
	}

	// Provider usage is per request, while Pi's context usage also accounts for
	// trailing messages after the last response. Scale the last request's
	// input/cache split to Pi's authoritative current context token count.
	const factor = contextTokens / inputSide;
	const cacheRead = Math.round(lastUsage.cacheRead * factor);
	const cacheWrite = Math.round(lastUsage.cacheWrite * factor);
	const input = Math.max(0, contextTokens - cacheRead - cacheWrite);
	return { input, output: lastUsage.output, cacheRead, cacheWrite };
}
