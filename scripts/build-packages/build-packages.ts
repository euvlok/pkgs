#!/usr/bin/env bun
import { buildApplication, buildCommand } from "@stricli/core";
import { array, parse, parseJson, pipe, string } from "valibot";
import { cliConfig, runCli } from "../cli/cli";
import { gha } from "../github-actions/github-actions";
import { nixCurrentSystem } from "../nix/nix";
import { nixString } from "../nix/syntax";
import { ExitError, run } from "../process/process";
import { REPO_ROOT } from "../repository/repository";

export function main(): void {
	const names = parse(
		pipe(string(), parseJson(), array(string())),
		process.env.PACKAGES_JSON ?? "[]",
	);
	const system = nixCurrentSystem();
	const supported = names.filter((name) => {
		const result = run(
			[
				"nix",
				"eval",
				"--accept-flake-config",
				"--impure",
				"--raw",
				"--expr",
				`
let
  flake = builtins.getFlake ${nixString(`path:${REPO_ROOT}`)};
  pkgs = builtins.getAttr ${nixString(system)} flake.legacyPackages;
  pkg = builtins.getAttr ${nixString(name)} pkgs;
  platforms = pkg.meta.platforms or [ ];
in if platforms == [ ] || builtins.elem ${nixString(system)} platforms then "true" else "false"
`,
			],
			{
				cwd: REPO_ROOT,
				check: true,
				capture: true,
				envExtra: { NIXPKGS_ALLOW_UNFREE: "1" },
			},
		);
		if (result.stdout.trim() === "true") return true;
		gha(
			"notice",
			`Skipping ${name} on ${system} because meta.platforms does not include this system`,
		);
		return false;
	});
	if (!supported.length) {
		gha("notice", `No selected packages are supported on ${system}`);
		return;
	}
	const attrs = supported.map((name) => `.#legacyPackages.${system}.${name}`);
	console.log(
		`Building ${attrs.length} package(s) for ${system}:\n${attrs.map((attr) => `  ${attr}`).join("\n")}`,
	);
	const result = run(
		[
			"nix",
			"build",
			"--accept-flake-config",
			"--impure",
			"--keep-going",
			"--print-build-logs",
			"--no-link",
			...attrs,
		],
		{ cwd: REPO_ROOT, envExtra: { NIXPKGS_ALLOW_UNFREE: "1" } },
	);
	if (result.returncode !== 0) throw new ExitError(result.returncode);
}

if (import.meta.main)
	await runCli(
		buildApplication(
			buildCommand({
				func: main,
				parameters: {},
				docs: {
					brief: "Build selected by-name packages supported on this system",
				},
			}),
			cliConfig("build-packages"),
		),
	);
