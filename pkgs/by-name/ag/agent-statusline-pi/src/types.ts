import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

export type DiffStats = { added: number; removed: number };
export type AssistantUsage = NonNullable<AssistantMessage["usage"]>;
export type TokenUsage = { input: number; output: number; cacheRead: number; cacheWrite: number };
export type ContextUsage = NonNullable<ReturnType<ExtensionContext["getContextUsage"]>>;
export type State = { headers?: Record<string, string>; diff: DiffStats; apiDurationMs: number };
export type SessionEntry = ReturnType<ExtensionContext["sessionManager"]["getEntries"]>[number];
export type Statusline = { schedule(force?: boolean): void; dispose(): void };
