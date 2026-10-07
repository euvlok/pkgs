import { nixEval, pkgWrapper } from "../nix/nix";
import { nixPath } from "../nix/syntax";
import { ExitError } from "../process/process";
import { logError, logInfo } from "./log";

export interface Metadata {
	owner: string;
	repo: string;
	updateScriptKind: "" | "string" | "path";
}
export function slug(meta: Metadata): string {
	return `${meta.owner}/${meta.repo}`;
}

export function extractMetadata(nixFile: string): Metadata {
	logInfo(`Checking metadata for '${nixFile}'...`);
	const meta = pkgWrapper(nixFile, (wrapper) => {
		const imported = `import ${nixPath(wrapper)}`;
		const updateType = nixEval(
			`let p = ${imported}; us = p.passthru.updateScript or null; in if us == null then "" else builtins.typeOf us`,
		);
		const kind =
			updateType === "string" ? "string" : updateType === "path" ? "path" : "";
		let owner: string;
		let repo: string;
		if (kind) {
			logInfo(`Found custom passthru.updateScript (${kind}) in package`);
			const match = nixEval(`(${imported}).meta.homepage or ""`).match(
				/^https:\/\/github\.com\/([^/]+)\/([^/]+)/,
			);
			owner = match?.[1] ?? "unknown";
			repo = match?.[2] ?? "unknown";
		} else {
			if (updateType)
				logInfo(
					`passthru.updateScript has type '${updateType}', falling back to nix-update`,
				);
			owner = nixEval(`(${imported}).src.owner`);
			repo = nixEval(`(${imported}).src.repo`);
			if (!owner || !repo) {
				logError(
					`Could not extract owner/repo from '${nixFile}'. Make sure that file contains 'owner' and 'repo' attributes.`,
					nixFile,
				);
				throw new ExitError();
			}
		}
		return { owner, repo, updateScriptKind: kind } satisfies Metadata;
	});
	logInfo(`Found repository: ${slug(meta)}`);
	return meta;
}
