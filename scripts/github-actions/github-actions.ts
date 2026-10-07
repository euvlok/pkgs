import { appendFileSync } from "node:fs";
import {
	debug,
	endGroup,
	error,
	notice,
	setOutput,
	startGroup,
	warning,
} from "@actions/core";

export type AnnotationKind = "error" | "warning" | "notice" | "debug";

export function gha(
	kind: AnnotationKind,
	message: string,
	file?: string,
): void {
	if (kind === "debug") debug(message);
	else ({ error, warning, notice })[kind](message, file ? { file } : undefined);
}

export function ghaGroup<T>(name: string, action: () => T): T {
	startGroup(name);
	try {
		return action();
	} finally {
		endGroup();
	}
}

export function ghaOutput(key: string, value: string): void {
	if (process.env.GITHUB_OUTPUT) setOutput(key, value);
}

export function ghaSummary(content: string): void {
	const path = process.env.GITHUB_STEP_SUMMARY;
	if (path) appendFileSync(path, content);
}
