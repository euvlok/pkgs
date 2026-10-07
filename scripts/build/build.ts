#!/usr/bin/env bun
import { rmSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "../..");
const commands = [
	"update",
	"status",
	"gen-pkg-table",
	"changed-packages",
	"build-packages",
];
const outdir = join(root, "dist");
rmSync(outdir, { recursive: true, force: true });
const result = await Bun.build({
	entrypoints: commands.map((name) =>
		join(root, "scripts", name, `${name}.ts`),
	),
	outdir,
	target: "bun",
	naming: { entry: "[name].[ext]", asset: "nix/[name].[ext]" },
});
if (!result.success)
	throw new AggregateError(result.logs, "Could not bundle the scripts");
for (const output of result.outputs) console.log(output.path);
