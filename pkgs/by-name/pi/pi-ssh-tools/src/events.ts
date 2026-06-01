import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createRemoteBashOps } from "./remote/bash";
import { updateSshStatus } from "./status";
import { disableSshTools } from "./tool-state";
import { transportLabel } from "./transport";
import type { ActiveSshTarget } from "./types";

type SshEventState = {
	getActiveTarget(): ActiveSshTarget | null;
	setActiveTarget(target: ActiveSshTarget | null): void;
};

export function registerSshEvents(pi: ExtensionAPI, state: SshEventState): void {
	pi.on("session_start", async (_event, ctx) => {
		state.setActiveTarget(null);
		disableSshTools(pi);
		updateSshStatus(ctx, null);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		state.setActiveTarget(null);
		disableSshTools(pi);
		updateSshStatus(ctx, null);
	});

	pi.on("user_bash", () => {
		const target = state.getActiveTarget();
		if (!target) return;
		const operations = createRemoteBashOps(target);
		return {
			operations: {
				exec: (command, _cwd, options) => operations.exec(command, target.remoteCwd, options),
			},
		};
	});

	pi.on("before_agent_start", async (event) => {
		const activeTarget = state.getActiveTarget();
		if (!activeTarget) {
			return;
		}
		return {
			systemPrompt:
				event.systemPrompt +
				`\n\nSSH mode is active for this turn.\nTransport: ${transportLabel(activeTarget.transport)}\nRemote host: ${activeTarget.remote}\nRemote working directory: ${activeTarget.remoteCwd}\nUse ssh_read, ssh_ls, ssh_find, ssh_write, ssh_edit, and ssh_bash for remote work. Local read/ls/find/write/edit/bash still operate on the local machine.`,
		};
	});
}
