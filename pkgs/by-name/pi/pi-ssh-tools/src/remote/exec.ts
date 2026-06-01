import { spawn } from "node:child_process";
import { SSH_COMMAND, TAILSCALE_COMMAND } from "../constants";
import { remotePathExpression } from "../shell";
import type { SshExecOptions, SshProfile, SshTransport } from "../types";

export function tailscaleAuthMessage(output: string): string | null {
	const match = output.match(/https:\/\/login\.tailscale\.com\/a\/[^\s]+/);
	if (!match) return null;
	return `Tailscale SSH needs browser authentication. Open this URL, approve the login, then run /ssh again:\n${match[0]}`;
}

export function sshExec(transport: SshTransport, remote: string, command: string, options: SshExecOptions = {}) {
	return new Promise<{ stdout: Buffer; stderr: Buffer; exitCode: number | null }>((resolve, reject) => {
		const child =
			transport === "tailscale"
				? spawn(TAILSCALE_COMMAND, ["ssh", remote, command], { stdio: ["pipe", "pipe", "pipe"] })
				: spawn(SSH_COMMAND, [remote, command], { stdio: ["pipe", "pipe", "pipe"] });
		const stdoutChunks: Buffer[] = [];
		const stderrChunks: Buffer[] = [];
		let timedOut = false;
		let detectedAuthMessage: string | null = null;
		const timer =
			typeof options.timeoutSeconds === "number" && options.timeoutSeconds > 0
				? setTimeout(() => {
						timedOut = true;
						child.kill();
					}, options.timeoutSeconds * 1000)
				: undefined;

		const cleanup = () => {
			if (timer) clearTimeout(timer);
			if (options.signal) options.signal.removeEventListener("abort", onAbort);
		};

		const onAbort = () => {
			child.kill();
		};

		child.stdout.on("data", (data: Buffer) => {
			stdoutChunks.push(data);
			detectedAuthMessage ??= tailscaleAuthMessage(data.toString("utf8"));
			if (detectedAuthMessage) child.kill();
			options.onStdoutData?.(data);
		});
		child.stderr.on("data", (data: Buffer) => {
			stderrChunks.push(data);
			detectedAuthMessage ??= tailscaleAuthMessage(data.toString("utf8"));
			if (detectedAuthMessage) child.kill();
			options.onStderrData?.(data);
		});
		child.on("error", (error) => {
			cleanup();
			if ((error as NodeJS.ErrnoException).code === "ENOENT") {
				reject(new Error(`${transport === "tailscale" ? TAILSCALE_COMMAND : SSH_COMMAND} command not found`));
				return;
			}
			reject(error);
		});
		child.on("close", (exitCode) => {
			cleanup();
			if (options.signal?.aborted) {
				reject(new Error("aborted"));
				return;
			}
			const stdout = Buffer.concat(stdoutChunks);
			const stderr = Buffer.concat(stderrChunks);
			const output = `${stdout.toString("utf8")}\n${stderr.toString("utf8")}`;
			const authMessage = detectedAuthMessage ?? tailscaleAuthMessage(output);
			if (authMessage) {
				reject(new Error(authMessage));
				return;
			}
			if (timedOut) {
				const detail = output.trim();
				reject(new Error(`SSH timed out after ${options.timeoutSeconds}s${detail ? `:\n${detail}` : ""}`));
				return;
			}
			resolve({
				stdout,
				stderr,
				exitCode,
			});
		});

		if (options.signal) {
			if (options.signal.aborted) {
				onAbort();
			} else {
				options.signal.addEventListener("abort", onAbort, { once: true });
			}
		}

		if (options.stdin !== undefined) {
			child.stdin.write(options.stdin);
		}
		child.stdin.end();
	});
}

export async function sshOk(transport: SshTransport, remote: string, command: string, options: SshExecOptions = {}): Promise<Buffer> {
	const { stdout, stderr, exitCode } = await sshExec(transport, remote, command, options);
	if (exitCode !== 0) {
		const combined = `${stdout.toString("utf8")}\n${stderr.toString("utf8")}`.trim();
		const authMessage = tailscaleAuthMessage(combined);
		if (authMessage) throw new Error(authMessage);
		throw new Error(`SSH failed (${exitCode}): ${combined || "unknown ssh error"}`);
	}
	return stdout;
}

export async function resolveRemoteCwd(profile: SshProfile): Promise<string> {
	if (profile.cwd?.trim()) {
		const requestedCwd = profile.cwd.trim();
		return (await sshOk(profile.transport, profile.remote, `cd ${remotePathExpression(requestedCwd)} && pwd`, { timeoutSeconds: 20 }))
			.toString("utf8")
			.trim();
	}
	return (await sshOk(profile.transport, profile.remote, "pwd", { timeoutSeconds: 20 })).toString("utf8").trim();
}
