import { chmodSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { nixCurrentSystem, nixEval, pkgWrapper } from "../nix/nix";
import { nixPath, nixString } from "../nix/syntax";
import { ExitError, run, withTempDir } from "../process/process";
import { REPO_ROOT } from "../repository/repository";
import { logError, logInfo } from "./log";
import { type Metadata, slug } from "./metadata";

export function runPathUpdateScript(nixFile: string, wrapper: string): void {
	const scriptPath = nixEval(
		`toString (import ${nixPath(wrapper)} {}).pkg.passthru.updateScript`,
	);
	if (
		!scriptPath ||
		!statSync(scriptPath, { throwIfNoEntry: false })?.isFile()
	) {
		logError(`Could not resolve path updateScript for '${nixFile}'`);
		throw new ExitError();
	}
	try {
		chmodSync(scriptPath, 0o755);
	} catch {
		/* Nix store paths may already be executable */
	}
	if (
		run([scriptPath], { envExtra: { UPDATE_FILE: nixFile } }).returncode !== 0
	) {
		logError("updateScript failed", nixFile);
		throw new ExitError();
	}
}

export function runStringUpdateScript(nixFile: string, meta: Metadata): void {
	logInfo("Executing updateScript...");
	console.log();
	const name = basename(dirname(nixFile));
	withTempDir(
		`${name}-update-`,
		(dir) => {
			const outLink = join(dir, "result");
			pkgWrapper(nixFile, (wrapper) => {
				writeFileSync(
					wrapper,
					`{ pkgs ? import <nixpkgs> {} }:\nlet\n  pkg = pkgs.callPackage ${nixPath(nixFile)} {};\nin pkgs.writeShellScriptBin ${nixString(`${name}-update-script`)} (builtins.readFile pkg.passthru.updateScript)\n`,
				);
				const build = run([
					"nix",
					"build",
					"--impure",
					"--file",
					wrapper,
					"--out-link",
					outLink,
					"--print-build-logs",
				]);
				if (build.returncode !== 0) {
					logError(`Failed to build updateScript for ${slug(meta)}`, nixFile);
					throw new ExitError();
				}
				const binDir = join(outLink, "bin");
				const binary = Bun.which(`${name}-update-script`, { PATH: binDir });
				if (!binary) {
					logError(`No executable found in ${binDir}`);
					throw new ExitError();
				}
				if (
					run([binary], { envExtra: { UPDATE_FILE: nixFile } }).returncode !== 0
				) {
					logError("updateScript failed");
					throw new ExitError();
				}
			});
		},
		process.env.TEMP_DIR,
	);
}

let updateBin: string | undefined;
export function nixUpdateBin(): string {
	if (updateBin) return updateBin;
	const onPath = Bun.which("nix-update");
	if (onPath) {
		updateBin = onPath;
		return onPath;
	}
	const result = run(
		[
			"nix",
			"build",
			"--impure",
			"--no-link",
			"--print-out-paths",
			`.#legacyPackages.${nixCurrentSystem()}.nix-update`,
		],
		{
			cwd: REPO_ROOT,
			capture: true,
			envExtra: { NIXPKGS_ALLOW_UNFREE: "1" },
		},
	);
	if (result.returncode !== 0) {
		logError("nix-update is not on PATH and could not be built from the flake");
		throw new ExitError();
	}
	updateBin = join(result.stdout.trim(), "bin", "nix-update");
	return updateBin;
}

export function runNixUpdate(
	nixFile: string,
	wrapper: string,
	version: string,
	meta: Metadata,
	subpackages: string[],
): void {
	const result = run([
		nixUpdateBin(),
		`--version=${version}`,
		...subpackages.map((name) => `--subpackage=${name}`),
		"-f",
		wrapper,
		"--override-filename",
		nixFile,
		"pkg",
	]);
	if (result.returncode !== 0) {
		logError(`nix-update failed for ${slug(meta)}`, nixFile);
		throw new ExitError();
	}
}
