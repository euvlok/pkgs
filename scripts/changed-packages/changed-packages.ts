#!/usr/bin/env bun
import { buildApplication, buildCommand } from "@stricli/core";
import { cliConfig, runCli } from "../cli/cli";
import { ghaOutput } from "../github-actions/github-actions";
import {
	allPackages,
	changedPackages,
	gitDiffFiles,
	isInfraFile,
	parsePackageSelection,
	resolveBase,
} from "./selection";

export function main(values: {
	base: string;
	head: string;
	packages: string;
	allOnInfra: boolean;
	changedOnlyOnInfra: boolean;
}): void {
	let packages: string[];
	if (values.packages.trim()) {
		console.log(`Using explicit package selection: ${values.packages}`);
		packages = parsePackageSelection(values.packages);
	} else {
		const base = resolveBase(values.base, values.head);
		console.log(`Diffing ${base}..${values.head}`);
		const files = gitDiffFiles(base, values.head);
		const infra = files.some(isInfraFile);
		if (infra && values.allOnInfra && !values.changedOnlyOnInfra) {
			console.log("Infra file changed, building all packages");
			packages = allPackages();
		} else {
			if (infra)
				console.log(
					"Infra file changed, but automatic full builds are disabled; building only changed packages",
				);
			packages = changedPackages(files);
		}
	}
	const payload = JSON.stringify(packages);
	console.log(`Packages: ${payload}`);
	ghaOutput("packages", payload);
	ghaOutput("has_packages", packages.length ? "true" : "false");
}

if (import.meta.main)
	await runCli(
		buildApplication(
			buildCommand({
				func: main,
				parameters: {
					flags: {
						base: {
							kind: "parsed",
							parse: String,
							default: process.env.BASE_SHA ?? "",
							brief: "Base revision to diff from",
						},
						head: {
							kind: "parsed",
							parse: String,
							default: process.env.HEAD_SHA ?? "HEAD",
							brief: "Head revision to diff to",
						},
						packages: {
							kind: "parsed",
							parse: String,
							default: process.env.PACKAGES ?? "",
							brief:
								"Names separated by commas or whitespace; 'all' selects every package",
						},
						allOnInfra: {
							kind: "boolean",
							default: /^(1|true|yes|on)$/i.test(
								process.env.ALL_ON_INFRA ?? "",
							),
							brief: "Build every package when infrastructure changes",
						},
						changedOnlyOnInfra: {
							kind: "boolean",
							brief: "Build only changed packages when infrastructure changes",
						},
					},
				},
				docs: { brief: "Emit changed packages and their local dependents" },
			}),
			cliConfig("changed-packages"),
		),
	);
