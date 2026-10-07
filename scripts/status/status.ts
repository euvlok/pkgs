#!/usr/bin/env bun
import { basename, dirname } from "node:path";
import { buildApplication, buildCommand } from "@stricli/core";
import Table from "cli-table3";
import colors from "picocolors";
import { cliConfig, runCli } from "../cli/cli";
import { nixCurrentSystem } from "../nix/nix";
import { nixStringAttr } from "../nix/syntax";
import { BY_NAME, packageFiles } from "../repository/repository";
import { classify, comparePins, packageStates } from "./versions";

export function main(values: { byName: string; system: string }): void {
	const system = values.system || nixCurrentSystem();
	const files = packageFiles(values.byName);
	console.error("Evaluating package versions...");
	const states = packageStates(
		system,
		files.map((file) => basename(dirname(file))),
	);
	const rows: [string, string, string][] = files.map((file) => {
		const name = basename(dirname(file));
		const state = states[name];
		return [
			name,
			state?.pin || nixStringAttr(file, "upstreamVersion") || "<none>",
			state?.upstream ?? "",
		];
	});
	const comparisons = comparePins(rows);
	console.log(`Package Pin Status (${system})`);
	const style = {
		behind: colors.red,
		"fork-only": colors.yellow,
		leading: colors.cyan,
		"no-pin": colors.dim,
		synced: colors.green,
		unknown: colors.magenta,
	};
	const table = new Table({
		head: ["Package", "Pin", "Nixpkgs Master", "Flake Effective", "Status"],
		style: { head: [], border: [] },
	});
	table.push(
		...rows.map(([name, pin, upstream]) => {
			const effective = states[name]?.effective ?? "?";
			const status = classify(pin, upstream, effective, comparisons[name]);
			const paint =
				style[status.replace(" (dormant)", "") as keyof typeof style] ?? String;
			return [
				colors.bold(name),
				pin,
				upstream || "<not-in-nixpkgs>",
				effective,
				paint(status),
			];
		}),
	);
	console.log(table.toString());
}

if (import.meta.main)
	await runCli(
		buildApplication(
			buildCommand({
				func: main,
				parameters: {
					flags: {
						byName: {
							kind: "parsed",
							parse: String,
							default: BY_NAME,
							brief: "Root of the by-name package tree",
						},
						system: {
							kind: "parsed",
							parse: String,
							default: "",
							brief: "System to evaluate (defaults to builtins.currentSystem)",
						},
					},
				},
				docs: {
					brief: "Report local package pin status against nixpkgs master",
				},
			}),
			cliConfig("status"),
		),
	);
