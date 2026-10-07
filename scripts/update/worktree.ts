import { gha } from "../github-actions/github-actions";
import { ExitError, run } from "../process/process";
import { REPO_ROOT } from "../repository/repository";

export function dirtyPaths(path: string): string[] {
	return run(
		["git", "status", "--porcelain", "--untracked-files=all", "--", path],
		{ cwd: REPO_ROOT, capture: true, check: true },
	)
		.stdout.split(/\r?\n/)
		.filter(Boolean);
}

export function requireCleanWorktree(): void {
	const dirty = dirtyPaths(REPO_ROOT);
	if (!dirty.length) return;
	gha(
		"error",
		`Refusing to update a dirty worktree; commit or stash these paths first:\n${dirty.join("\n")}`,
	);
	throw new ExitError();
}

// Callers guarantee a clean starting tree before an update can be restored
export function restorePackage(pkgDir: string): void {
	run(
		["git", "restore", "--source=HEAD", "--staged", "--worktree", "--", pkgDir],
		{ cwd: REPO_ROOT, check: true },
	);
	run(["git", "clean", "-fd", "--", pkgDir], { cwd: REPO_ROOT, check: true });
}

export function pkgHasChanges(pkgDir: string): boolean {
	return dirtyPaths(pkgDir).length > 0;
}

export function commitPkg(name: string, pkgDir: string): boolean {
	run(["git", "add", "--", pkgDir], { cwd: REPO_ROOT, check: true });
	if (
		run(["git", "diff", "--staged", "--quiet", "--", pkgDir], {
			cwd: REPO_ROOT,
		}).returncode === 0
	)
		return false;
	run(["git", "commit", "-m", `${name}: bump`, "--", pkgDir], {
		cwd: REPO_ROOT,
		check: true,
	});
	return true;
}
