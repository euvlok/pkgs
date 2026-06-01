import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerSshCommand } from "./src/commands";
import { registerSshEvents } from "./src/events";
import { registerSshTools } from "./src/tools";
import type { ActiveSshTarget } from "./src/types";

export default function sshToolsExtension(pi: ExtensionAPI): void {
	let activeTarget: ActiveSshTarget | null = null;

	const state = {
		getActiveTarget: () => activeTarget,
		setActiveTarget: (target: ActiveSshTarget | null) => {
			activeTarget = target;
		},
		requireActiveTarget: (): ActiveSshTarget => {
			if (!activeTarget) {
				throw new Error("SSH mode is off. Use /ssh <host> first.");
			}
			return activeTarget;
		},
	};

	registerSshTools(pi, state);
	registerSshCommand(pi, state);
	registerSshEvents(pi, state);
}
