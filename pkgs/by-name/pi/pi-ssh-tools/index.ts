import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { extname, join } from "node:path";
import {
	type BashOperations,
	createBashToolDefinition,
	createEditToolDefinition,
	createReadToolDefinition,
	createWriteToolDefinition,
	type EditOperations,
	type ExtensionAPI,
	type ExtensionCommandContext,
	type ExtensionContext,
	type ReadOperations,
	type WriteOperations,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

type SshTransport = "ssh" | "tailscale";

type SshProfile = {
	name: string;
	remote: string;
	transport: SshTransport;
	cwd?: string;
};

type ActiveSshTarget = {
	name: string;
	remote: string;
	transport: SshTransport;
	remoteCwd: string;
};

type SshExecOptions = {
	stdin?: string | Buffer;
	signal?: AbortSignal;
	onStdoutData?: (data: Buffer) => void;
	onStderrData?: (data: Buffer) => void;
	timeoutSeconds?: number;
};

const SSH_STATUS_KEY = "ssh-tools";
const SSH_TOOL_NAMES = ["ssh_read", "ssh_write", "ssh_edit", "ssh_bash"] as const;
const SSH_CONFIG_PATH = join(homedir(), ".ssh", "config");
const SSH_COMMAND = "ssh";
const TAILSCALE_COMMAND = "tailscale";

function shellQuote(value: string): string {
	return `'${value.replaceAll("'", `'"'"'`)}'`;
}

function parseSshConfigProfiles(): SshProfile[] {
	if (!existsSync(SSH_CONFIG_PATH)) {
		return [];
	}

	const text = readFileSync(SSH_CONFIG_PATH, "utf8");
	const profiles = new Map<string, SshProfile>();

	for (const rawLine of text.split("\n")) {
		const withoutComment = rawLine.replace(/\s+#.*$/, "").trim();
		if (!withoutComment) continue;

		const match = withoutComment.match(/^Host\s+(.+)$/i);
		if (!match) continue;

		const aliases = match[1]!
			.split(/\s+/)
			.map((alias) => alias.trim())
			.filter(Boolean)
			.filter((alias) => !alias.includes("*") && !alias.includes("?") && !alias.startsWith("!"));

		for (const alias of aliases) {
			if (!profiles.has(alias)) {
				profiles.set(alias, { name: alias, remote: alias, transport: "ssh" });
			}
		}
	}

	return Array.from(profiles.values()).sort((a, b) => a.name.localeCompare(b.name));
}

function parseTransportPrefix(input: string): { transport: SshTransport; target: string; explicit: boolean } {
	const trimmed = input.trim();
	const lower = trimmed.toLowerCase();
	for (const [prefix, transport] of [
		["tailscale:", "tailscale"],
		["ts:", "tailscale"],
		["ssh:", "ssh"],
		["plain:", "ssh"],
	] as const) {
		if (lower.startsWith(prefix)) {
			return { transport, target: trimmed.slice(prefix.length), explicit: true };
		}
	}
	return { transport: "tailscale", target: trimmed, explicit: false };
}

function normalizeTargetArg(arg: string, profiles: SshProfile[]): SshProfile {
	const parsed = parseTransportPrefix(arg);
	const trimmed = parsed.target.trim();
	const matchedProfile = profiles.find((profile) => profile.name === trimmed);
	if (matchedProfile && !parsed.explicit) {
		return matchedProfile;
	}

	const separatorIndex = trimmed.indexOf(":");
	if (separatorIndex > 0) {
		return {
			name: `${parsed.transport}:${trimmed}`,
			remote: trimmed.slice(0, separatorIndex),
			transport: parsed.transport,
			cwd: trimmed.slice(separatorIndex + 1),
		};
	}

	return { name: `${parsed.transport}:${trimmed}`, remote: trimmed, transport: parsed.transport };
}

function inferImageMimeType(path: string): string | null {
	switch (extname(path).toLowerCase()) {
		case ".jpg":
		case ".jpeg":
			return "image/jpeg";
		case ".png":
			return "image/png";
		case ".gif":
			return "image/gif";
		case ".webp":
			return "image/webp";
		default:
			return null;
	}
}

function tailscaleAuthMessage(output: string): string | null {
	const match = output.match(/https:\/\/login\.tailscale\.com\/a\/[^\s]+/);
	if (!match) return null;
	return `Tailscale SSH needs browser authentication. Open this URL, approve the login, then run /ssh again:\n${match[0]}`;
}

function transportLabel(transport: SshTransport): string {
	return transport === "tailscale" ? "Tailscale SSH" : "SSH";
}

function sshExec(transport: SshTransport, remote: string, command: string, options: SshExecOptions = {}) {
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

async function sshOk(
	transport: SshTransport,
	remote: string,
	command: string,
	options: SshExecOptions = {},
): Promise<Buffer> {
	const { stdout, stderr, exitCode } = await sshExec(transport, remote, command, options);
	if (exitCode !== 0) {
		const combined = `${stdout.toString("utf8")}\n${stderr.toString("utf8")}`.trim();
		const authMessage = tailscaleAuthMessage(combined);
		if (authMessage) throw new Error(authMessage);
		throw new Error(`SSH failed (${exitCode}): ${combined || "unknown ssh error"}`);
	}
	return stdout;
}

async function resolveRemoteCwd(profile: SshProfile): Promise<string> {
	if (profile.cwd?.trim()) {
		return profile.cwd.trim();
	}
	return (await sshOk(profile.transport, profile.remote, "pwd", { timeoutSeconds: 20 })).toString("utf8").trim();
}

function createRemoteReadOps(target: ActiveSshTarget): ReadOperations {
	return {
		readFile: (absolutePath) => sshOk(target.transport, target.remote, `cat ${shellQuote(absolutePath)}`),
		access: (absolutePath) =>
			sshOk(target.transport, target.remote, `test -r ${shellQuote(absolutePath)}`).then(() => {}),
		detectImageMimeType: async (absolutePath) => inferImageMimeType(absolutePath),
	};
}

function createRemoteWriteOps(target: ActiveSshTarget): WriteOperations {
	return {
		writeFile: async (absolutePath, content) => {
			await sshOk(target.transport, target.remote, `cat > ${shellQuote(absolutePath)}`, { stdin: content });
		},
		mkdir: (dir) => sshOk(target.transport, target.remote, `mkdir -p ${shellQuote(dir)}`).then(() => {}),
	};
}

function createRemoteEditOps(target: ActiveSshTarget): EditOperations {
	const readOps = createRemoteReadOps(target);
	const writeOps = createRemoteWriteOps(target);
	return {
		readFile: readOps.readFile,
		writeFile: writeOps.writeFile,
		access: (absolutePath) =>
			sshOk(
				target.transport,
				target.remote,
				`test -r ${shellQuote(absolutePath)} && test -w ${shellQuote(absolutePath)}`,
			).then(() => {}),
	};
}

function createRemoteBashOps(target: ActiveSshTarget): BashOperations {
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

function enableSshTools(pi: ExtensionAPI) {
	const next = new Set(pi.getActiveTools());
	for (const name of SSH_TOOL_NAMES) {
		next.add(name);
	}
	pi.setActiveTools(Array.from(next));
}

function disableSshTools(pi: ExtensionAPI) {
	const next = pi.getActiveTools().filter((name) => !SSH_TOOL_NAMES.includes(name as (typeof SSH_TOOL_NAMES)[number]));
	pi.setActiveTools(next);
}

export default function sshToolsExtension(pi: ExtensionAPI) {
	let activeTarget: ActiveSshTarget | null = null;

	const readBase = createReadToolDefinition("/");
	const writeBase = createWriteToolDefinition("/");
	const editBase = createEditToolDefinition("/");
	const bashBase = createBashToolDefinition("/");

	const requireActiveTarget = (): ActiveSshTarget => {
		if (!activeTarget) {
			throw new Error("SSH mode is off. Use /ssh <host> first.");
		}
		return activeTarget;
	};

	const refreshProfiles = () => parseSshConfigProfiles();

	const updateStatus = (ctx: ExtensionContext) => {
		if (!activeTarget) {
			ctx.ui.setStatus(SSH_STATUS_KEY, undefined);
			return;
		}
		ctx.ui.setStatus(
			SSH_STATUS_KEY,
			ctx.ui.theme.fg(
				"accent",
				`${transportLabel(activeTarget.transport)} ${activeTarget.remote}:${activeTarget.remoteCwd}`,
			),
		);
	};

	const activate = async (profile: SshProfile, ctx: ExtensionCommandContext) => {
		ctx.ui.notify(`Connecting with ${transportLabel(profile.transport)}: ${profile.remote}...`, "info");
		try {
			const remoteCwd = await resolveRemoteCwd(profile);
			activeTarget = {
				name: profile.name,
				remote: profile.remote,
				transport: profile.transport,
				remoteCwd,
			};
			enableSshTools(pi);
			updateStatus(ctx);
			ctx.ui.notify(
				`${transportLabel(activeTarget.transport)} mode on: ${activeTarget.remote} (${activeTarget.remoteCwd})`,
				"info",
			);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			ctx.ui.notify(`Could not connect to ${profile.remote} with ${transportLabel(profile.transport)}:\n${message}`, "error");
			ctx.ui.setEditorText(`/ssh ${profile.name}`);
		}
	};

	const deactivate = (ctx: ExtensionCommandContext) => {
		activeTarget = null;
		disableSshTools(pi);
		updateStatus(ctx);
		ctx.ui.notify("SSH mode off", "info");
	};

	pi.registerTool({
		name: "ssh_read",
		label: "ssh_read",
		description: "Read a file on the active SSH host. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Read file contents on the active SSH host",
		promptGuidelines: ["Use ssh_read when the task is on the active SSH host instead of the local machine."],
		parameters: readBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = requireActiveTarget();
			const tool = createReadToolDefinition(target.remoteCwd, { operations: createRemoteReadOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme) {
			const path = typeof args?.path === "string" ? args.path : "...";
			const targetLabel = activeTarget ? activeTarget.name : "inactive";
			return new Text(
				`${theme.fg("toolTitle", theme.bold("ssh_read"))} ${theme.fg("accent", path)} ${theme.fg("muted", `[${targetLabel}]`)}`,
				0,
				0,
			);
		},
		renderResult: readBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_write",
		label: "ssh_write",
		description: "Write a text file on the active SSH host. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Create or overwrite files on the active SSH host",
		promptGuidelines: ["Use ssh_write only for new files or full rewrites on the active SSH host."],
		parameters: writeBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = requireActiveTarget();
			const tool = createWriteToolDefinition(target.remoteCwd, { operations: createRemoteWriteOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme) {
			const path = typeof args?.path === "string" ? args.path : "...";
			const targetLabel = activeTarget ? activeTarget.name : "inactive";
			return new Text(
				`${theme.fg("toolTitle", theme.bold("ssh_write"))} ${theme.fg("accent", path)} ${theme.fg("muted", `[${targetLabel}]`)}`,
				0,
				0,
			);
		},
		renderResult: writeBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_edit",
		label: "ssh_edit",
		description: "Edit a file on the active SSH host using exact text replacement. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Make precise file edits on the active SSH host",
		promptGuidelines: [
			"Use ssh_edit for precise remote changes.",
			"Each edits[].oldText must match exactly on the remote file.",
		],
		parameters: editBase.parameters,
		prepareArguments: editBase.prepareArguments,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = requireActiveTarget();
			const tool = createEditToolDefinition(target.remoteCwd, { operations: createRemoteEditOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme) {
			const path = typeof args?.path === "string" ? args.path : "...";
			const targetLabel = activeTarget ? activeTarget.name : "inactive";
			return new Text(
				`${theme.fg("toolTitle", theme.bold("ssh_edit"))} ${theme.fg("accent", path)} ${theme.fg("muted", `[${targetLabel}]`)}`,
				0,
				0,
			);
		},
		renderResult: editBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_bash",
		label: "ssh_bash",
		description: "Execute a bash command on the active SSH host in the active remote working directory.",
		promptSnippet: "Execute bash commands on the active SSH host",
		promptGuidelines: ["Use ssh_bash when the command must run on the active SSH host rather than locally."],
		parameters: bashBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = requireActiveTarget();
			const tool = createBashToolDefinition(target.remoteCwd, { operations: createRemoteBashOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const command = typeof args?.command === "string" ? args.command : "...";
			const targetLabel = activeTarget ? activeTarget.name : "inactive";
			const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
			text.setText(
				`${theme.fg("toolTitle", theme.bold("ssh_bash"))} ${theme.fg("accent", command)} ${theme.fg("muted", `[${targetLabel}]`)}`,
			);
			return text;
		},
		renderResult: bashBase.renderResult,
	});

	pi.registerCommand("ssh", {
		description: "Toggle remote SSH tools: /ssh, /ssh off, /ssh status, /ssh [ts:|ssh:]<host>[:/path]",
		getArgumentCompletions: (prefix) => {
			const options = ["off", "status", "ts:", "tailscale:", "ssh:", ...refreshProfiles().map((profile) => profile.name)];
			const filtered = options.filter((option) => option.startsWith(prefix));
			return filtered.length > 0 ? filtered.map((option) => ({ value: option, label: option })) : null;
		},
		handler: async (args, ctx) => {
			await ctx.waitForIdle();
			const input = args.trim();
			const profiles = refreshProfiles();

			if (input === "status") {
				if (!activeTarget) {
					ctx.ui.notify("SSH mode is off", "info");
					return;
				}
				ctx.ui.notify(
					`${transportLabel(activeTarget.transport)} mode: ${activeTarget.remote}:${activeTarget.remoteCwd}`,
					"info",
				);
				return;
			}

			if (input === "off") {
				if (!activeTarget) {
					ctx.ui.notify("SSH mode is already off", "info");
					return;
				}
				deactivate(ctx);
				return;
			}

			if (!input) {
				if (profiles.length === 0) {
					ctx.ui.notify("No SSH hosts found in ~/.ssh/config. Use /ssh [ts:|ssh:]<host>[:/path]", "warning");
					return;
				}
				const items = [...(activeTarget ? ["off"] : []), ...profiles.map((profile) => profile.name)];
				const picked = await ctx.ui.select("SSH target", items);
				if (!picked) {
					return;
				}
				if (picked === "off") {
					deactivate(ctx);
					return;
				}
				await activate(normalizeTargetArg(picked, profiles), ctx);
				return;
			}

			await activate(normalizeTargetArg(input, profiles), ctx);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		activeTarget = null;
		disableSshTools(pi);
		updateStatus(ctx);
	});

	pi.on("before_agent_start", async (event) => {
		if (!activeTarget) {
			return;
		}
		return {
			systemPrompt:
				event.systemPrompt +
				`\n\nSSH mode is active for this turn.\nTransport: ${transportLabel(activeTarget.transport)}\nRemote host: ${activeTarget.remote}\nRemote working directory: ${activeTarget.remoteCwd}\nUse ssh_read, ssh_write, ssh_edit, and ssh_bash for remote work. Local read/write/edit/bash still operate on the local machine.`,
		};
	});
}
