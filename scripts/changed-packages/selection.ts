import { basename, dirname } from "node:path";
import { nixTopLevelFormalArgs } from "../nix/syntax";
import { ExitError, run } from "../process/process";
import { packageFiles, REPO_ROOT } from "../repository/repository";

const INFRA_FILES = new Set([
	"flake.nix",
	"flake.lock",
	"default.nix",
	".github/workflows/build-packages.yaml",
	"package.json",
	"bun.lock",
]);
const INFRA_PREFIXES = [
	".github/actions/setup-nix/",
	".github/actions/setup-bun/",
	"scripts/",
];
const ZERO_SHA = "0".repeat(40);

export function gitDiffFiles(base: string, head: string): string[] {
	return run(["git", "diff", "--name-only", base, head], {
		cwd: REPO_ROOT,
		capture: true,
		check: true,
	})
		.stdout.split(/\r?\n/)
		.filter(Boolean);
}

export function resolveBase(base: string, head: string): string {
	if (base && base !== ZERO_SHA) return base;
	const result = run(["git", "rev-parse", `${head}^`], {
		cwd: REPO_ROOT,
		capture: true,
	});
	return result.returncode === 0 ? result.stdout.trim() : head;
}

export function packageNixFiles(): Map<string, string> {
	return new Map(packageFiles().map((file) => [basename(dirname(file)), file]));
}

export function allPackages(): string[] {
	return [...packageNixFiles().keys()].sort();
}

export function isInfraFile(path: string): boolean {
	return (
		INFRA_FILES.has(path) ||
		INFRA_PREFIXES.some((prefix) => path.startsWith(prefix))
	);
}

export function localDependencyGraph(): Map<string, Set<string>> {
	const files = packageNixFiles();
	return new Map(
		[...files].map(([name, file]) => [
			name,
			new Set([...nixTopLevelFormalArgs(file)].filter((arg) => files.has(arg))),
		]),
	);
}

export function includeLocalDependents(packages: string[]): string[] {
	const reverseDeps = new Map<string, Set<string>>();
	for (const [name, deps] of localDependencyGraph()) {
		for (const dep of deps) {
			let dependents = reverseDeps.get(dep);
			if (!dependents) {
				dependents = new Set();
				reverseDeps.set(dep, dependents);
			}
			dependents.add(name);
		}
	}
	const expanded = new Set(packages);
	const queue = [...packages];
	for (let index = 0; index < queue.length; index++) {
		for (const dependent of reverseDeps.get(queue[index] ?? "") ?? []) {
			if (!expanded.has(dependent)) {
				expanded.add(dependent);
				queue.push(dependent);
			}
		}
	}
	return [...expanded].sort();
}

export function parsePackageSelection(packages: string): string[] {
	const tokens = packages
		.trim()
		.split(/[\s,]+/)
		.filter(Boolean);
	if (!tokens.length) return [];
	if (tokens.includes("all")) return allPackages();
	const files = packageNixFiles();
	const invalid = [
		...new Set(tokens.filter((token) => !files.has(token))),
	].sort();
	if (invalid.length) {
		console.error(`Unknown package(s): ${invalid.join(", ")}`);
		throw new ExitError();
	}
	return includeLocalDependents([...new Set(tokens)].sort());
}

export function changedPackages(files: string[]): string[] {
	const existing = packageNixFiles();
	const names = new Set<string>();
	for (const file of files) {
		const parts = file.split("/");
		const name = parts[3];
		if (
			parts.length >= 4 &&
			parts[0] === "pkgs" &&
			parts[1] === "by-name" &&
			name &&
			existing.has(name)
		)
			names.add(name);
	}
	return includeLocalDependents([...names].sort());
}
