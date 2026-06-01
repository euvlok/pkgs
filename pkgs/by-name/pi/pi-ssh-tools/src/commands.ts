import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { normalizeTargetArg, parseProfiles } from "./profiles";
import { resolveRemoteCwd } from "./remote/exec";
import { updateSshStatus } from "./status";
import { disableSshTools, enableSshTools } from "./tool-state";
import { transportLabel } from "./transport";
import type { ActiveSshTarget, SshProfile } from "./types";

type SshCommandState = {
	getActiveTarget(): ActiveSshTarget | null;
	setActiveTarget(target: ActiveSshTarget | null): void;
};

export function registerSshCommand(pi: ExtensionAPI, state: SshCommandState): void {
	const refreshProfiles = () => parseProfiles();

	const activate = async (profile: SshProfile, ctx: ExtensionCommandContext) => {
		ctx.ui.notify(`Connecting with ${transportLabel(profile.transport)}: ${profile.remote}...`, "info");
		try {
			const remoteCwd = await resolveRemoteCwd(profile);
			const activeTarget = {
				name: profile.name,
				remote: profile.remote,
				transport: profile.transport,
				remoteCwd,
			};
			state.setActiveTarget(activeTarget);
			enableSshTools(pi);
			updateSshStatus(ctx, activeTarget);
			ctx.ui.notify(`${transportLabel(activeTarget.transport)} mode on: ${activeTarget.remote} (${activeTarget.remoteCwd})`, "info");
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			ctx.ui.notify(`Could not connect to ${profile.remote} with ${transportLabel(profile.transport)}:\n${message}`, "error");
			ctx.ui.setEditorText(`/ssh ${profile.name}`);
		}
	};

	const deactivate = (ctx: ExtensionCommandContext) => {
		state.setActiveTarget(null);
		disableSshTools(pi);
		updateSshStatus(ctx, null);
		ctx.ui.notify("SSH mode off", "info");
	};

	pi.registerCommand("ssh", {
		description: "Toggle remote SSH tools (ssh_read/ls/find/write/edit/bash): /ssh, /ssh off, /ssh status, /ssh [ts:|ssh:]<host>[:/path]",
		getArgumentCompletions: (prefix) => {
			const staticOptions = ["off", "status", "ts:", "tailscale:", "ssh:"].map((option) => ({ value: option, label: option }));
			const profileOptions = refreshProfiles().map((profile) => ({
				value: profile.name,
				label: profile.name,
				description: profile.description,
			}));
			const filtered = [...staticOptions, ...profileOptions].filter((option) => option.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			await ctx.waitForIdle();
			const input = args.trim();
			const profiles = refreshProfiles();
			const activeTarget = state.getActiveTarget();

			if (input === "status") {
				if (!activeTarget) {
					ctx.ui.notify("SSH mode is off", "info");
					return;
				}
				ctx.ui.notify(`${transportLabel(activeTarget.transport)} mode: ${activeTarget.remote}:${activeTarget.remoteCwd}`, "info");
				return;
			}

			if (input === "off") {
				if (!activeTarget) {
					ctx.ui.notify("SSH mode is already off", "info");
					return;
				}
				deactivate(ctx);
				return;
			}

			if (!input) {
				if (profiles.length === 0) {
					ctx.ui.notify("No SSH hosts found in ~/.ssh/config and no Tailscale peers found. Use /ssh [ts:|ssh:]<host>[:/path]", "warning");
					return;
				}
				const items = [...(activeTarget ? ["off"] : []), ...profiles.map((profile) => profile.name)];
				const picked = await ctx.ui.select("SSH target", items);
				if (!picked) {
					return;
				}
				if (picked === "off") {
					deactivate(ctx);
					return;
				}
				await activate(normalizeTargetArg(picked, profiles), ctx);
				return;
			}

			await activate(normalizeTargetArg(input, profiles), ctx);
		},
	});
}
