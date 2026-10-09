import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import {
	type GenericSchema,
	type InferOutput,
	parse,
	parseJson,
	pipe,
	string,
} from "valibot";
import { run, withTempDir } from "../process/process";
import { REPO_ROOT } from "../repository/repository";
import packageSetFile from "../update/package-set.nix" with { type: "file" };
import { nixPath, nixString } from "./syntax";

export function nixEval(expr: string, check = false): string {
	const result = run(["nix", "eval", "--impure", "--raw", "--expr", expr], {
		capture: true,
		check,
	});
	return result.returncode === 0 ? result.stdout.trim() : "";
}

export function nixEvalJson<T extends GenericSchema>(
	expr: string,
	schema: T,
): InferOutput<T> {
	const result = run(["nix", "eval", "--impure", "--json", "--expr", expr], {
		cwd: REPO_ROOT,
		capture: true,
		envExtra: { NIXPKGS_ALLOW_UNFREE: "1" },
		check: true,
	});
	return parse(pipe(string(), parseJson(), schema), result.stdout);
}

export function nixEvalFileJson<T extends GenericSchema>(
	nixFile: string,
	args: Record<string, string>,
	schema: T,
): InferOutput<T> {
	const argFlags = Object.entries(args).flatMap(([name, value]) => [
		"--argstr",
		name,
		value,
	]);
	const result = run(
		[
			"nix-instantiate",
			"--eval",
			"--strict",
			"--json",
			"--impure",
			nixFile,
			...argFlags,
		],
		{
			cwd: REPO_ROOT,
			capture: true,
			envExtra: { NIXPKGS_ALLOW_UNFREE: "1" },
			check: true,
		},
	);
	return parse(pipe(string(), parseJson(), schema), result.stdout);
}

let currentSystem: string | undefined;
export function nixCurrentSystem(): string {
	currentSystem ??= nixEval("builtins.currentSystem", true);
	return currentSystem;
}

export function pkgWrapper<T>(
	nixFile: string,
	action: (wrapper: string) => T,
): T {
	return withTempDir("nix-update-", (dir) => {
		const wrapper = join(dir, "wrapper.nix");
		writeFileSync(
			wrapper,
			`{ }: import ${nixPath(resolve(import.meta.dir, packageSetFile))} { repoRoot = ${nixString(REPO_ROOT)}; nixFile = ${nixString(nixFile)}; }\n`,
		);
		return action(wrapper);
	});
}
