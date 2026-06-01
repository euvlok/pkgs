import { posix } from "node:path";
import type { LsOperations } from "@earendil-works/pi-coding-agent";
import { shellQuote } from "../shell";
import type { ActiveSshTarget } from "../types";
import { sshExec, sshOk } from "./exec";

export function createRemoteLsOps(target: ActiveSshTarget): LsOperations {
	const statCache = new Map<string, boolean>();
	return {
		exists: async (absolutePath) => {
			const { exitCode } = await sshExec(target.transport, target.remote, `test -e ${shellQuote(absolutePath)}`, {
				timeoutSeconds: 10,
			});
			return exitCode === 0;
		},
		stat: async (absolutePath) => {
			const cachedIsDirectory = statCache.get(absolutePath);
			if (cachedIsDirectory !== undefined) return { isDirectory: () => cachedIsDirectory };
			const { exitCode } = await sshExec(target.transport, target.remote, `test -d ${shellQuote(absolutePath)}`, {
				timeoutSeconds: 10,
			});
			const isDirectory = exitCode === 0;
			statCache.set(absolutePath, isDirectory);
			return { isDirectory: () => isDirectory };
		},
		readdir: async (absolutePath) => {
			const script = `dir=${shellQuote(absolutePath)}
for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
	[ -e "$entry" ] || continue
	name=\${entry##*/}
	if [ -d "$entry" ]; then type=d; else type=f; fi
	printf '%s\t%s\n' "$type" "$name"
done`;
			const stdout = await sshOk(target.transport, target.remote, script, { timeoutSeconds: 20 });
			const entries: string[] = [];
			for (const line of stdout.toString("utf8").split("\n")) {
				if (!line) continue;
				const separatorIndex = line.indexOf("\t");
				if (separatorIndex <= 0) continue;
				const type = line.slice(0, separatorIndex);
				const entry = line.slice(separatorIndex + 1);
				entries.push(entry);
				statCache.set(posix.join(absolutePath, entry), type === "d");
			}
			return entries;
		},
	};
}
