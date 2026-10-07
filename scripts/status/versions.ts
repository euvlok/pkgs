import { resolve } from "node:path";
import { type InferOutput, number, object, record, string } from "valibot";
import { nixEvalFileJson, nixEvalJson } from "../nix/nix";
import { nixString } from "../nix/syntax";
import { REPO_ROOT } from "../repository/repository";
import packageStatesFile from "./package-states.nix" with { type: "file" };

const packageStateSchema = object({
	effective: string(),
	pin: string(),
	upstream: string(),
});
export type PackageState = InferOutput<typeof packageStateSchema>;
const NIXPKGS_MASTER = "github:NixOS/nixpkgs/master";

export function packageStates(
	system: string,
	names: string[],
): Record<string, PackageState> {
	return nixEvalFileJson(
		resolve(import.meta.dir, packageStatesFile),
		{
			upstreamFlakeRef: NIXPKGS_MASTER,
			localFlakeRef: `path:${REPO_ROOT}`,
			system,
			namesJson: JSON.stringify(names),
		},
		record(string(), packageStateSchema),
	);
}

export function comparePins(
	rows: [string, string, string][],
): Record<string, number> {
	const pairs = rows
		.filter(
			([, pin, upstream]) => pin !== "<none>" && upstream && upstream !== "?",
		)
		.map(([name, pin, upstream]) => ({ name, pin, upstream }));
	if (!pairs.length) return {};
	return nixEvalJson(
		`let pairs = builtins.fromJSON ${nixString(JSON.stringify(pairs))}; in builtins.listToAttrs (map (p: { name = p.name; value = builtins.compareVersions p.pin p.upstream; }) pairs)`,
		record(string(), number()),
	);
}

export function classify(
	pin: string,
	upstream: string,
	effective: string,
	comparison?: number,
): string {
	if (pin === "<none>") return "no-pin";
	if (upstream === "?") return "unknown";
	if (!upstream) return "fork-only";
	if (comparison === undefined) return "unknown";
	let status =
		({ 1: "leading", 0: "synced", "-1": "behind" } as Record<number, string>)[
			comparison
		] ?? "unknown";
	if (effective !== pin && effective !== "?") status += " (dormant)";
	return status;
}
