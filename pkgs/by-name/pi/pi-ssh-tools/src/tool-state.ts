import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { SSH_TOOL_NAMES } from "./constants";

export function enableSshTools(pi: ExtensionAPI): void {
	const next = new Set(pi.getActiveTools());
	for (const name of SSH_TOOL_NAMES) {
		next.add(name);
	}
	pi.setActiveTools(Array.from(next));
}

export function disableSshTools(pi: ExtensionAPI): void {
	const next = pi.getActiveTools().filter((name) => !SSH_TOOL_NAMES.includes(name as (typeof SSH_TOOL_NAMES)[number]));
	pi.setActiveTools(next);
}
