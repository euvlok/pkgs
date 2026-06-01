import { Text } from "@earendil-works/pi-tui";
import type { ActiveSshTarget } from "./types";

export function renderSshToolCall(
	toolName: string,
	value: string,
	activeTarget: ActiveSshTarget | null,
	theme: { fg(color: string, text: string): string; bold(text: string): string },
	context: { lastComponent?: unknown },
) {
	const targetLabel = activeTarget ? activeTarget.name : "inactive";
	const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
	text.setText(`${theme.fg("toolTitle", theme.bold(toolName))} ${theme.fg("accent", value)} ${theme.fg("muted", `[${targetLabel}]`)}`);
	return text;
}
