import type { ReadOperations } from "@earendil-works/pi-coding-agent";
import { inferImageMimeType } from "../path";
import { shellQuote } from "../shell";
import type { ActiveSshTarget } from "../types";
import { sshOk } from "./exec";

export function createRemoteReadOps(target: ActiveSshTarget): ReadOperations {
	return {
		readFile: (absolutePath) => sshOk(target.transport, target.remote, `cat ${shellQuote(absolutePath)}`),
		access: (absolutePath) => sshOk(target.transport, target.remote, `test -r ${shellQuote(absolutePath)}`).then(() => {}),
		detectImageMimeType: async (absolutePath) => {
			try {
				const mime = (
					await sshOk(target.transport, target.remote, `file --mime-type -b ${shellQuote(absolutePath)}`, { timeoutSeconds: 10 })
				)
					.toString("utf8")
					.trim();
				if (["image/jpeg", "image/png", "image/gif", "image/webp"].includes(mime)) return mime;
			} catch {
				// Fall back to extension-based detection below.
			}
			return inferImageMimeType(absolutePath);
		},
	};
}
