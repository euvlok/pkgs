#!/usr/bin/env bun
import { accessSync, constants, statSync } from "node:fs";
import { resolve } from "node:path";
import { buildApplication, buildCommand, buildRouteMap } from "@stricli/core";
import { cliConfig, runCli } from "../cli/cli";
import { BY_NAME } from "../repository/repository";
import { cmdAll } from "./all";
import { updateOne } from "./package";

const versionFlag = {
	kind: "parsed",
	parse: String,
	default: "branch",
	brief: "Version argument for nix-update",
} as const;

function readableFile(input: string): string {
	if (!statSync(input, { throwIfNoEntry: false })?.isFile())
		throw new Error(`Not a readable file: ${input}`);
	accessSync(input, constants.R_OK);
	return resolve(input);
}

const pkgCommand = buildCommand({
	func: (flags: { version: string; subpackage?: string[] }, nixFile: string) =>
		updateOne(nixFile, flags.version, flags.subpackage),
	parameters: {
		flags: {
			version: versionFlag,
			subpackage: {
				kind: "parsed",
				parse: String,
				optional: true,
				variadic: true,
				brief: "Child derivation hash to bump (repeatable)",
			},
		},
		positional: {
			kind: "tuple",
			parameters: [
				{
					parse: readableFile,
					brief: "Path to a package.nix under pkgs/by-name",
					placeholder: "package.nix",
				},
			],
		},
	},
	docs: { brief: "Update a single package" },
});
const allCommand = buildCommand({
	func: (flags: { byName: string; version: string }) =>
		cmdAll(flags.byName, flags.version),
	parameters: {
		flags: {
			version: versionFlag,
			byName: {
				kind: "parsed",
				parse: String,
				default: BY_NAME,
				brief: "Root of the by-name package tree",
			},
		},
	},
	docs: {
		brief: "Update fetchable packages, verify builds, and commit each bump",
	},
});

if (import.meta.main)
	await runCli(
		buildApplication(
			buildRouteMap({
				routes: { pkg: pkgCommand, all: allCommand },
				docs: { brief: "Update by-name Nix packages" },
			}),
			cliConfig("update"),
		),
	);
