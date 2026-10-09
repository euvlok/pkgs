import { basename } from "node:path";
import { ExitError, run } from "../process/process";
import { REPO_ROOT } from "../repository/repository";
import { logError } from "./log";
import { type Metadata, slug } from "./metadata";

export function runUpdateScript(
	nixFile: string,
	wrapper: string,
	meta: Metadata,
	version?: string,
	subpackages: string[] = [],
): void {
	const nixUpdate = basename(meta.command[0] ?? "") === "nix-update";
	const args: string[] = [];
	if (nixUpdate) {
		args.push("-f", wrapper);
		if (
			!meta.command.some(
				(arg) =>
					arg === "--override-filename" ||
					arg.startsWith("--override-filename="),
			)
		)
			args.push("--override-filename", nixFile);
		if (version !== undefined) args.push(`--version=${version}`);
		args.push(...subpackages.map((name) => `--subpackage=${name}`));
	}
	// Build the command to realize generated scripts and their runtime dependencies
	const build = run(
		[
			"nix",
			"build",
			"--impure",
			"--no-link",
			"--print-out-paths",
			"--file",
			wrapper,
			"updater",
		],
		{
			cwd: REPO_ROOT,
			capture: true,
		},
	);
	if (build.returncode !== 0) {
		logError(
			`Could not build updater for ${slug(meta)}:\n${build.stderr}`,
			nixFile,
		);
		throw new ExitError();
	}
	const result = run([build.stdout.trim(), ...args], {
		cwd: REPO_ROOT,
		envExtra: {
			UPDATE_FILE: nixFile,
			UPDATE_NIX_NAME: meta.name,
			UPDATE_NIX_PNAME: meta.pname,
			UPDATE_NIX_OLD_VERSION: meta.version,
			UPDATE_NIX_ATTR_PATH: meta.attrPath,
			NIXPKGS_ALLOW_UNFREE: "1",
			// This runner supplies a file context, including when launched by nix run
			UPDATE_NIX_FLAKE: "0",
		},
	});
	if (result.returncode !== 0) {
		logError(`Update failed for ${slug(meta)}`, nixFile);
		throw new ExitError();
	}
}
