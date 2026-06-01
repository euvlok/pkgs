import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { SSH_STATUS_KEY } from "./constants";
import { transportLabel } from "./transport";
import type { ActiveSshTarget } from "./types";

export function updateSshStatus(ctx: ExtensionContext, activeTarget: ActiveSshTarget | null): void {
	if (!ctx.hasUI) return;
	if (!activeTarget) {
		ctx.ui.setStatus(SSH_STATUS_KEY, undefined);
		return;
	}
	ctx.ui.setStatus(
		SSH_STATUS_KEY,
		ctx.ui.theme.fg("accent", `${transportLabel(activeTarget.transport)} ${activeTarget.remote}:${activeTarget.remoteCwd}`),
	);
}
