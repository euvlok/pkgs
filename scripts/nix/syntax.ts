import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export function nixStringAttr(nixFile: string, key: string): string {
	return (
		readFileSync(nixFile, "utf8").match(
			new RegExp(`^\\s*${RegExp.escape(key)}\\s*=\\s*"([^"]*)"\\s*;`, "m"),
		)?.[1] ?? ""
	);
}

export function nixTopLevelFormalArgs(nixFile: string): Set<string> {
	const content = readFileSync(nixFile, "utf8").replace(/#.*$/gm, "");
	const body = content.match(/^\s*\{(.*?)\}\s*:/s)?.[1];
	return new Set(
		body
			?.split(",")
			.flatMap(
				(item) => item.match(/^\s*([A-Za-z_][A-Za-z0-9_'-]*)/)?.[1] ?? [],
			) ?? [],
	);
}

// Construct a path expression without interpreting spaces or Nix interpolation
export function nixPath(path: string): string {
	return `(builtins.toPath ${nixString(resolve(path))})`;
}

export function nixString(value: string): string {
	return JSON.stringify(value).replaceAll("${", "\\${");
}
