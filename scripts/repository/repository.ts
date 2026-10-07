import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

function repositoryRoot(): string {
	if (process.env.EUPKGS_REPO_ROOT)
		return resolve(process.env.EUPKGS_REPO_ROOT);
	let candidate = import.meta.dir;
	while (true) {
		if (
			existsSync(join(candidate, "flake.nix")) &&
			existsSync(join(candidate, "pkgs", "by-name"))
		)
			return candidate;
		const parent = dirname(candidate);
		if (parent === candidate)
			throw new Error(
				"Could not find the eupkgs checkout; set EUPKGS_REPO_ROOT",
			);
		candidate = parent;
	}
}

export const REPO_ROOT = repositoryRoot();
export const BY_NAME = join(REPO_ROOT, "pkgs", "by-name");

export function packageFiles(byName = BY_NAME): string[] {
	return [
		...new Bun.Glob("*/*/package.nix").scanSync({
			cwd: byName,
			absolute: true,
			onlyFiles: true,
		}),
	].sort();
}
