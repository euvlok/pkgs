import { parseTransportPrefix } from "../transport";
import type { SshProfile } from "../types";
import { parseSshConfigProfiles } from "./ssh-config";
import { parseTailscaleStatusProfilesCached } from "./tailscale";

export function parseProfiles(): SshProfile[] {
	const profiles = new Map<string, SshProfile>();
	for (const profile of [...parseSshConfigProfiles(), ...parseTailscaleStatusProfilesCached()]) {
		profiles.set(profile.name, profile);
	}
	return Array.from(profiles.values()).sort((a, b) => (a.sortRank ?? 0) - (b.sortRank ?? 0) || a.name.localeCompare(b.name));
}

function splitTargetAndCwd(input: string): { target: string; cwd?: string } {
	const trimmed = input.trim();
	if (trimmed.startsWith("[")) {
		const closeBracket = trimmed.indexOf("]");
		if (closeBracket > 1 && trimmed.slice(closeBracket + 1).startsWith(":")) {
			const cwd = trimmed.slice(closeBracket + 2);
			return { target: trimmed.slice(1, closeBracket), cwd: cwd || undefined };
		}
	}

	const separator = trimmed.match(/:(?=\/|~)/);
	if (!separator?.index) return { target: trimmed };
	return {
		target: trimmed.slice(0, separator.index),
		cwd: trimmed.slice(separator.index + 1) || undefined,
	};
}

export function normalizeTargetArg(arg: string, profiles: SshProfile[]): SshProfile {
	const parsed = parseTransportPrefix(arg);
	const { target, cwd } = splitTargetAndCwd(parsed.target);
	const trimmed = target.trim();
	const matchedProfile = profiles.find(
		(profile) => profile.name === trimmed || (parsed.transport === "tailscale" && profile.name === `ts:${trimmed}`),
	);
	if (matchedProfile && (!parsed.explicit || matchedProfile.transport === parsed.transport)) {
		return { ...matchedProfile, cwd: cwd ?? matchedProfile.cwd };
	}

	return { name: `${parsed.transport}:${trimmed}`, remote: trimmed, transport: parsed.transport, cwd };
}
