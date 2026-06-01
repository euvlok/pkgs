import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { pollIntervalMs } from "./src/constants";
import { systemTheme } from "./src/system-theme";

export default function catppuccinSystemThemeExtension(pi: ExtensionAPI): void {
	let intervalId: ReturnType<typeof setInterval> | undefined;
	let checking = false;

	const stopPolling = (): void => {
		if (intervalId !== undefined) {
			clearInterval(intervalId);
			intervalId = undefined;
		}
	};

	pi.on("session_start", async (_event, ctx) => {
		stopPolling();
		if (!ctx.hasUI) return;

		let currentTheme = "";
		const applyTheme = async (): Promise<void> => {
			if (checking) return;
			checking = true;
			try {
				const nextTheme = await systemTheme();
				if (nextTheme === currentTheme) return;

				const result = ctx.ui.setTheme(nextTheme);
				if (!result.success) {
					ctx.ui.notify(`Could not set ${nextTheme}: ${result.error ?? "unknown theme error"}`, "warning");
					return;
				}
				currentTheme = nextTheme;
			} finally {
				checking = false;
			}
		};

		await applyTheme();
		intervalId = setInterval(() => void applyTheme(), pollIntervalMs);
		intervalId.unref?.();
	});

	pi.on("session_shutdown", () => {
		stopPolling();
	});
}
