import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const execFileAsync = promisify(execFile);

const darkTheme = "catppuccin-frappe";
const lightTheme = "catppuccin-latte";
const pollIntervalMs = 2000;

async function commandSucceeds(file: string, args: readonly string[] = []): Promise<boolean> {
	try {
		await execFileAsync(file, [...args]);
		return true;
	} catch {
		return false;
	}
}

async function isDarwinDarkMode(): Promise<boolean> {
	return await commandSucceeds("defaults", ["read", "-g", "AppleInterfaceStyle"]);
}

async function isGnomeDarkMode(): Promise<boolean> {
	try {
		const { stdout } = await execFileAsync("gsettings", ["get", "org.gnome.desktop.interface", "color-scheme"], {
			encoding: "utf8",
		});
		return stdout.toLowerCase().includes("dark");
	} catch {
		return true;
	}
}

async function isDarkMode(): Promise<boolean> {
	return process.platform === "darwin" ? await isDarwinDarkMode() : await isGnomeDarkMode();
}

async function systemTheme(): Promise<string> {
	return (await isDarkMode()) ? darkTheme : lightTheme;
}

export default function catppuccinSystemThemeExtension(pi: ExtensionAPI): void {
	let intervalId: ReturnType<typeof setInterval> | undefined;

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;

		let currentTheme = await systemTheme();
		ctx.ui.setTheme(currentTheme);

		intervalId = setInterval(async () => {
			const nextTheme = await systemTheme();
			if (nextTheme !== currentTheme) {
				currentTheme = nextTheme;
				ctx.ui.setTheme(currentTheme);
			}
		}, pollIntervalMs);
	});

	pi.on("session_shutdown", () => {
		if (intervalId !== undefined) {
			clearInterval(intervalId);
			intervalId = undefined;
		}
	});
}
