import { mkdtempDisposableSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export class ExitError extends Error {
	readonly exitCode: number;
	constructor(exitCode = 1) {
		super(`Command exited with status ${exitCode}`);
		this.exitCode = exitCode;
	}
}

export interface RunOptions {
	cwd?: string;
	check?: boolean;
	capture?: boolean;
	envExtra?: Record<string, string>;
}

export interface RunResult {
	returncode: number;
	stdout: string;
	stderr: string;
}

export function run(cmd: string[], options: RunOptions = {}): RunResult {
	const result = Bun.spawnSync(cmd, {
		cwd: options.cwd,
		env: options.envExtra
			? { ...process.env, ...options.envExtra }
			: process.env,
		stdin: "inherit",
		stdout: options.capture ? "pipe" : "inherit",
		stderr: options.capture ? "pipe" : "inherit",
	});
	const output = {
		returncode: result.exitCode,
		stdout: result.stdout?.toString() ?? "",
		stderr: result.stderr?.toString() ?? "",
	};
	if (options.check && result.exitCode !== 0) {
		throw new Error(
			`${cmd[0]} exited with status ${result.exitCode}${output.stderr ? `:\n${output.stderr}` : ""}`,
		);
	}
	return output;
}

export function withTempDir<T>(
	prefix: string,
	action: (dir: string) => T,
	root = tmpdir(),
): T {
	using dir = mkdtempDisposableSync(join(root, prefix));
	return action(dir.path);
}
