import type { SshTransport } from "./types";

export function transportLabel(transport: SshTransport): string {
	return transport === "tailscale" ? "Tailscale SSH" : "SSH";
}

export function parseTransportPrefix(input: string): { transport: SshTransport; target: string; explicit: boolean } {
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
