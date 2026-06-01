import type { EditOperations } from "@earendil-works/pi-coding-agent";
import { shellQuote } from "../shell";
import type { ActiveSshTarget } from "../types";
import { sshOk } from "./exec";
import { createRemoteReadOps } from "./read";
import { createRemoteWriteOps } from "./write";

export function createRemoteEditOps(target: ActiveSshTarget): EditOperations {
	const readOps = createRemoteReadOps(target);
	const writeOps = createRemoteWriteOps(target);
	return {
		readFile: readOps.readFile,
		writeFile: writeOps.writeFile,
		access: (absolutePath) =>
			sshOk(target.transport, target.remote, `test -r ${shellQuote(absolutePath)} && test -w ${shellQuote(absolutePath)}`).then(() => {}),
	};
}
