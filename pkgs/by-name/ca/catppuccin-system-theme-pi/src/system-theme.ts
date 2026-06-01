import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { darkTheme, lightTheme } from "./constants";

const execFileAsync = promisify(execFile);

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

export async function isDarkMode(): Promise<boolean> {
	return process.platform === "darwin" ? await isDarwinDarkMode() : await isGnomeDarkMode();
}

export async function systemTheme(): Promise<string> {
	return (await isDarkMode()) ? darkTheme : lightTheme;
}
