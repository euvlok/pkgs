import { isEditToolResult, isWriteToolResult, type ToolResultEvent } from "@earendil-works/pi-coding-agent";
import type { DiffStats } from "./types";

export const zeroDiff = (): DiffStats => ({ added: 0, removed: 0 });

export function diffFromToolResult(event: ToolResultEvent): DiffStats {
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
