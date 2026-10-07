import { realpathSync } from "node:fs";
import { basename, dirname } from "node:path";
import { ghaGroup, ghaSummary } from "../github-actions/github-actions";
import { nixCurrentSystem, pkgWrapper } from "../nix/nix";
import { run } from "../process/process";
import { REPO_ROOT } from "../repository/repository";
import {
	runNixUpdate,
	runPathUpdateScript,
	runStringUpdateScript,
} from "./execution";
import { logInfo, logNotice } from "./log";
import { extractMetadata, type Metadata, slug } from "./metadata";

export function writePkgSummary(
	nixFile: string,
	meta: Metadata,
	version: string,
): void {
	ghaSummary(
		`### ${basename(dirname(nixFile))}\n- Repository: \`${slug(meta)}\`\n${meta.updateScriptKind ? "" : `- Version: \`${version}\`\n`}- File: \`${nixFile}\`\n`,
	);
}

export function updateOne(
	nixFile: string,
	version = "branch",
	subpackages: string[] = [],
): void {
	const absolute = realpathSync(nixFile);
	ghaGroup(`Package update: ${nixFile}`, () => {
		const meta = extractMetadata(absolute);
		logInfo(`Updating '${absolute}' for ${slug(meta)}...`);
		logNotice(`Updating ${slug(meta)}`, absolute);
		if (meta.updateScriptKind === "string")
			runStringUpdateScript(absolute, meta);
		else
			pkgWrapper(
				absolute,
				(wrapper) => {
					if (meta.updateScriptKind === "path")
						runPathUpdateScript(absolute, wrapper);
					else runNixUpdate(absolute, wrapper, version, meta, subpackages);
				},
				true,
			);
		writePkgSummary(absolute, meta, version);
		logNotice("Package update completed successfully!");
	});
}

export function isFetchableDerivation(pkgPath: string): boolean {
	const attr = `.#legacyPackages.${nixCurrentSystem()}.${basename(dirname(pkgPath))}`;
	const options = {
		cwd: REPO_ROOT,
		capture: true,
		envExtra: { NIXPKGS_ALLOW_UNFREE: "1" },
	};
	const result = run(
		["nix", "eval", "--impure", "--raw", `${attr}.type`],
		options,
	);
	if (result.returncode !== 0 || result.stdout.trim() !== "derivation")
		return false;
	const source = run(
		["nix", "eval", "--impure", "--raw", `${attr}.src.drvPath`],
		options,
	);
	return source.returncode === 0 && Boolean(source.stdout.trim());
}

export function buildPkg(pkgPath: string): boolean {
	return (
		run(
			[
				"nix",
				"build",
				"--impure",
				"--no-link",
				"--print-build-logs",
				"--option",
				"sandbox",
				"true",
				`.#legacyPackages.${nixCurrentSystem()}.${basename(dirname(pkgPath))}`,
			],
			{
				cwd: REPO_ROOT,
				envExtra: { NIXPKGS_ALLOW_UNFREE: "1" },
			},
		).returncode === 0
	);
}
