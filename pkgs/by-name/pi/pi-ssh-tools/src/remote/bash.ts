import type { BashOperations } from "@earendil-works/pi-coding-agent";
import { shellQuote } from "../shell";
import type { ActiveSshTarget } from "../types";
import { sshExec } from "./exec";

export function createRemoteBashOps(target: ActiveSshTarget): BashOperations {
	return {
		exec: async (command, cwd, { onData, signal, timeout }) => {
			const script = `cd ${shellQuote(cwd)}\n${command}\n`;
			const { exitCode } = await sshExec(target.transport, target.remote, `exec "\${SHELL:-/bin/sh}" -lc 'exec bash -se'`, {
				stdin: script,
				signal,
				timeoutSeconds: timeout,
				onStdoutData: onData,
				onStderrData: onData,
			});
			return { exitCode };
		},
	};
}
