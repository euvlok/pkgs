#!/usr/bin/env bun
import { basename, dirname, relative, resolve } from "node:path";
import { buildApplication, buildCommand } from "@stricli/core";
import { markdownTable } from "markdown-table";
import { type InferOutput, object, record, string } from "valibot";
import { cliConfig, runCli } from "../cli/cli";
import { nixCurrentSystem, nixEvalFileJson } from "../nix/nix";
import { nixStringAttr } from "../nix/syntax";
import { BY_NAME, packageFiles, REPO_ROOT } from "../repository/repository";
import packageMetadataFile from "./package-metadata.nix" with { type: "file" };

const packageMetadataSchema = object({
	version: string(),
	description: string(),
});
export type PackageMetadata = InferOutput<typeof packageMetadataSchema>;

export function flakePackageMetadata(
	system: string,
	names: string[],
): Record<string, PackageMetadata> {
	return nixEvalFileJson(
		resolve(import.meta.dir, packageMetadataFile),
		{
			localFlakeRef: `path:${REPO_ROOT}`,
			system,
			namesJson: JSON.stringify(names),
		},
		record(string(), packageMetadataSchema),
	);
}

export function rows(): string[][] {
	const files = packageFiles(BY_NAME);
	console.error("Evaluating packages...");
	const metadata = flakePackageMetadata(
		nixCurrentSystem(),
		files.map((file) => basename(dirname(file))),
	);
	return files.map((file) => {
		const name = basename(dirname(file));
		const pkg = metadata[name];
		const version = pkg?.version || nixStringAttr(file, "version");
		const description = pkg?.description || nixStringAttr(file, "description");
		return [
			`[\`${name}\`](${relative(REPO_ROOT, dirname(file))})`,
			`\`${version || "?"}\``,
			description,
		];
	});
}

export function main(): void {
	console.log(
		markdownTable(
			[["Package", "Version", "Description"], ...rows()].map((row) =>
				row.map((cell) => cell.replaceAll("|", "\\|").replace(/\r?\n/g, " ")),
			),
		),
	);
}

if (import.meta.main)
	await runCli(
		buildApplication(
			buildCommand({
				func: main,
				parameters: {},
				docs: {
					brief:
						"Print a GitHub-flavored Markdown table of every by-name package",
				},
			}),
			cliConfig("gen-pkg-table"),
		),
	);
