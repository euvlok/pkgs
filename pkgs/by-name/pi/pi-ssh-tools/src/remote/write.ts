import type { WriteOperations } from "@earendil-works/pi-coding-agent";
import { shellQuote } from "../shell";
import type { ActiveSshTarget } from "../types";
import { sshOk } from "./exec";

export function createRemoteWriteOps(target: ActiveSshTarget): WriteOperations {
	return {
		writeFile: async (absolutePath, content) => {
			await sshOk(target.transport, target.remote, `cat > ${shellQuote(absolutePath)}`, { stdin: content });
		},
		mkdir: (dir) => sshOk(target.transport, target.remote, `mkdir -p ${shellQuote(dir)}`).then(() => {}),
	};
}
