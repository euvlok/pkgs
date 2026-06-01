import type { FindOperations } from "@earendil-works/pi-coding-agent";
import { shellQuote } from "../shell";
import type { ActiveSshTarget } from "../types";
import { sshExec, sshOk } from "./exec";

function ignoredDirectoryNames(ignore: string[]): string[] {
	const names = new Set([".git", "node_modules"]);
	for (const pattern of ignore) {
		if (pattern.includes("node_modules")) names.add("node_modules");
		if (pattern.includes(".git")) names.add(".git");
	}
	return Array.from(names);
}

function normalizeRemoteFindLine(line: string): string | null {
	const trimmed = line.trim().replace(/^\.\//, "").replace(/\/$/, "");
	return trimmed && trimmed !== "." ? trimmed : null;
}

function remoteFindAbsolutePath(cwd: string, entry: string): string {
	const base = cwd.replace(/\/$/, "");
	// Pi's find renderer relativizes custom absolute results by slicing
	// searchPath.length + 1. For root, "//name" round-trips to "name".
	return base ? `${base}/${entry}` : `//${entry}`;
}

async function findRemoteFdCommand(target: ActiveSshTarget): Promise<string | null> {
	try {
		const stdout = await sshOk(target.transport, target.remote, "command -v fd || command -v fdfind", { timeoutSeconds: 5 });
		return stdout.toString("utf8").split("\n")[0]?.trim() || null;
	} catch {
		return null;
	}
}

export function createRemoteFindOps(target: ActiveSshTarget): FindOperations {
	let fdCommandPromise: Promise<string | null> | null = null;
	return {
		exists: async (absolutePath) => {
			const { exitCode } = await sshExec(target.transport, target.remote, `test -e ${shellQuote(absolutePath)}`, {
				timeoutSeconds: 10,
			});
			return exitCode === 0;
		},
		glob: async (pattern, cwd, { ignore, limit }) => {
			const effectiveLimit = Math.max(1, Math.floor(limit));
			fdCommandPromise ??= findRemoteFdCommand(target);
			const fdCommand = await fdCommandPromise;
			let stdout: Buffer;
			if (fdCommand) {
				const args = ["--glob", "--color=never", "--hidden", "--no-require-git", "--max-results", String(effectiveLimit)];
				for (const ignoredName of ignoredDirectoryNames(ignore)) {
					args.push("--exclude", ignoredName);
				}
				let effectivePattern = pattern;
				if (pattern.includes("/")) {
					args.push("--full-path");
					if (!pattern.startsWith("/") && !pattern.startsWith("**/") && pattern !== "**") {
						effectivePattern = `**/${pattern}`;
					}
				}
				args.push("--", effectivePattern, ".");
				const script = `cd ${shellQuote(cwd)} && ${shellQuote(fdCommand)} ${args.map(shellQuote).join(" ")}`;
				stdout = await sshOk(target.transport, target.remote, script, { timeoutSeconds: 30 });
			} else {
				const prunes = ignoredDirectoryNames(ignore)
					.map((name) => `-name ${shellQuote(name)}`)
					.join(" -o ");
				const predicate = pattern.includes("/")
					? `\\( -path ${shellQuote(`./${pattern}`)} -o -path ${shellQuote(`*/${pattern}`)} \\)`
					: `-name ${shellQuote(pattern)}`;
				const script = `cd ${shellQuote(cwd)} && find . \\( ${prunes} \\) -prune -o \\( -type f -o -type d \\) ${predicate} -print | head -n ${effectiveLimit}`;
				stdout = await sshOk(target.transport, target.remote, script, { timeoutSeconds: 30 });
			}
			return stdout
				.toString("utf8")
				.split("\n")
				.map(normalizeRemoteFindLine)
				.filter((entry): entry is string => Boolean(entry))
				.map((entry) => remoteFindAbsolutePath(cwd, entry));
		},
	};
}
