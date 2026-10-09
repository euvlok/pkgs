import { realpathSync } from "node:fs";
import { basename, dirname } from "node:path";
import { ghaGroup, ghaSummary } from "../github-actions/github-actions";
import { nixCurrentSystem, nixEval, pkgWrapper } from "../nix/nix";
import { nixPath } from "../nix/syntax";
import { run } from "../process/process";
import { REPO_ROOT } from "../repository/repository";
import { runUpdateScript } from "./execution";
import { logInfo, logNotice } from "./log";
import { extractMetadata, type Metadata, slug } from "./metadata";

export function writePkgSummary(
	nixFile: string,
	meta: Metadata,
	version?: string,
): void {
	ghaSummary(
		`### ${basename(dirname(nixFile))}\n- Repository: \`${slug(meta)}\`\n${version === undefined ? "" : `- Version: \`${version}\`\n`}- File: \`${nixFile}\`\n`,
	);
}

export function updateOne(
	nixFile: string,
	version?: string,
	subpackages: string[] = [],
): void {
	const absolute = realpathSync(nixFile);
	ghaGroup(`Package update: ${nixFile}`, () => {
		pkgWrapper(absolute, (wrapper) => {
			const meta = extractMetadata(wrapper);
			logInfo(`Updating '${absolute}' for ${slug(meta)}...`);
			logNotice(`Updating ${slug(meta)}`, absolute);
			runUpdateScript(absolute, wrapper, meta, version, subpackages);
			writePkgSummary(absolute, meta, version);
		});
		logNotice("Package update completed successfully!");
	});
}

export function isUpdateableDerivation(pkgPath: string): boolean {
	return pkgWrapper(
		pkgPath,
		(wrapper) =>
			nixEval(
				`if (import ${nixPath(wrapper)} {}).canUpdate then "yes" else "no"`,
			) === "yes",
	);
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
