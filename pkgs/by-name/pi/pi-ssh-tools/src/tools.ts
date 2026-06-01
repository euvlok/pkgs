import {
	createBashToolDefinition,
	createEditToolDefinition,
	createFindToolDefinition,
	createLsToolDefinition,
	createReadToolDefinition,
	createWriteToolDefinition,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { createRemoteBashOps } from "./remote/bash";
import { createRemoteEditOps } from "./remote/edit";
import { createRemoteFindOps } from "./remote/find";
import { createRemoteLsOps } from "./remote/ls";
import { createRemoteReadOps } from "./remote/read";
import { createRemoteWriteOps } from "./remote/write";
import { renderSshToolCall } from "./render";
import type { ActiveSshTarget } from "./types";

type SshToolState = {
	getActiveTarget(): ActiveSshTarget | null;
	requireActiveTarget(): ActiveSshTarget;
};

export function registerSshTools(pi: ExtensionAPI, state: SshToolState): void {
	const readBase = createReadToolDefinition("/");
	const lsBase = createLsToolDefinition("/");
	const findBase = createFindToolDefinition("/");
	const writeBase = createWriteToolDefinition("/");
	const editBase = createEditToolDefinition("/");
	const bashBase = createBashToolDefinition("/");

	pi.registerTool({
		name: "ssh_read",
		label: "ssh_read",
		description: "Read a file on the active SSH host. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Read file contents on the active SSH host",
		promptGuidelines: ["Use ssh_read when the task is on the active SSH host instead of the local machine."],
		parameters: readBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = state.requireActiveTarget();
			const tool = createReadToolDefinition(target.remoteCwd, { operations: createRemoteReadOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const path = typeof args?.path === "string" ? args.path : "...";
			return renderSshToolCall("ssh_read", path, state.getActiveTarget(), theme, context);
		},
		renderResult: readBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_ls",
		label: "ssh_ls",
		description: "List directory contents on the active SSH host. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "List directory contents on the active SSH host",
		promptGuidelines: ["Use ssh_ls when listing files on the active SSH host instead of the local machine."],
		parameters: lsBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = state.requireActiveTarget();
			const tool = createLsToolDefinition(target.remoteCwd, { operations: createRemoteLsOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const path = typeof args?.path === "string" ? args.path : ".";
			return renderSshToolCall("ssh_ls", path, state.getActiveTarget(), theme, context);
		},
		renderResult: lsBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_find",
		label: "ssh_find",
		description:
			"Find files by glob pattern on the active SSH host. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Find files by glob pattern on the active SSH host",
		promptGuidelines: [
			"Use ssh_find when searching for remote file names on the active SSH host instead of the local machine.",
			"ssh_find uses remote fd when available; otherwise it falls back to portable find and prunes .git/node_modules.",
		],
		parameters: findBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = state.requireActiveTarget();
			const tool = createFindToolDefinition(target.remoteCwd, { operations: createRemoteFindOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const pattern = typeof args?.pattern === "string" ? args.pattern : "...";
			return renderSshToolCall("ssh_find", pattern, state.getActiveTarget(), theme, context);
		},
		renderResult: findBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_write",
		label: "ssh_write",
		description: "Write a text file on the active SSH host. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Create or overwrite files on the active SSH host",
		promptGuidelines: ["Use ssh_write only for new files or full rewrites on the active SSH host."],
		parameters: writeBase.parameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = state.requireActiveTarget();
			const tool = createWriteToolDefinition(target.remoteCwd, { operations: createRemoteWriteOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const path = typeof args?.path === "string" ? args.path : "...";
			return renderSshToolCall("ssh_write", path, state.getActiveTarget(), theme, context);
		},
		renderResult: writeBase.renderResult,
	});

	pi.registerTool({
		name: "ssh_edit",
		label: "ssh_edit",
		description:
			"Edit a file on the active SSH host using exact text replacement. Relative paths are resolved against the active remote working directory.",
		promptSnippet: "Make precise file edits on the active SSH host",
		promptGuidelines: ["Use ssh_edit for precise remote changes.", "Each edits[].oldText must match exactly on the remote file."],
		parameters: editBase.parameters,
		prepareArguments: editBase.prepareArguments,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const target = state.requireActiveTarget();
			const tool = createEditToolDefinition(target.remoteCwd, { operations: createRemoteEditOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const path = typeof args?.path === "string" ? args.path : "...";
			return renderSshToolCall("ssh_edit", path, state.getActiveTarget(), theme, context);
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
			const target = state.requireActiveTarget();
			const tool = createBashToolDefinition(target.remoteCwd, { operations: createRemoteBashOps(target) });
			return tool.execute(toolCallId, params, signal, onUpdate, ctx);
		},
		renderCall(args, theme, context) {
			const command = typeof args?.command === "string" ? args.command : "...";
			return renderSshToolCall("ssh_bash", command, state.getActiveTarget(), theme, context);
		},
		renderResult: bashBase.renderResult,
	});
}
