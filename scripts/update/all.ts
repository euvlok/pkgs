import { basename, dirname } from "node:path";
import {
	gha,
	ghaGroup,
	ghaOutput,
	ghaSummary,
} from "../github-actions/github-actions";
import { ExitError } from "../process/process";
import { BY_NAME, packageFiles } from "../repository/repository";
import { toleratedFailureAnnotations } from "./log";
import { buildPkg, isFetchableDerivation, updateOne } from "./package";
import {
	commitPkg,
	pkgHasChanges,
	requireCleanWorktree,
	restorePackage,
} from "./worktree";

export function cmdAll(byName = BY_NAME, version = "branch"): void {
	if (!Bun.which("nix") || !Bun.which("git")) {
		gha("error", "nix and git must be on PATH");
		throw new ExitError();
	}
	requireCleanWorktree();
	const updated: string[] = [];
	for (const nixFile of packageFiles(byName)) {
		const pkgDir = dirname(nixFile);
		const name = basename(pkgDir);
		ghaGroup(`Updating ${name}`, () => {
			if (!isFetchableDerivation(nixFile)) {
				gha("notice", `Skipping ${name} (not a fetchable derivation)`, nixFile);
				return;
			}
			try {
				toleratedFailureAnnotations(() => updateOne(nixFile, version));
			} catch (error) {
				if (!(error instanceof ExitError)) throw error;
				gha("warning", `Update failed for ${name}`, nixFile);
				restorePackage(pkgDir);
				return;
			}
			if (!pkgHasChanges(pkgDir)) {
				gha("notice", `No changes for ${name}`, nixFile);
				return;
			}
			if (!buildPkg(nixFile)) {
				gha("warning", `Build failed for ${name} after update`, nixFile);
				restorePackage(pkgDir);
				return;
			}
			if (commitPkg(name, pkgDir)) {
				updated.push(`${name}|${pkgDir}`);
				gha("notice", `Updated ${name} successfully and build verified`);
			}
		});
	}
	ghaOutput("has_changes", updated.length ? "true" : "false");
	ghaOutput("updated_packages", updated.join("\n"));
	ghaSummary(
		updated.length
			? `### Updated packages\n\`\`\`\n${updated.join("\n")}\n\`\`\`\n`
			: "### No changes detected\nAll packages are up to date.\n",
	);
}
