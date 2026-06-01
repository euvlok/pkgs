import { spawnSync } from "node:child_process";
import { TAILSCALE_COMMAND } from "../constants";
import { stripTrailingDot } from "../path";
import type { SshProfile, TailscalePeerStatus, TailscaleStatus } from "../types";

function basenameFromDNSName(dnsName: string, magicDNSSuffix?: string): string | null {
	const trimmed = stripTrailingDot(dnsName);
	if (magicDNSSuffix) {
		const suffix = `.${stripTrailingDot(magicDNSSuffix)}`;
		if (trimmed.toLowerCase().endsWith(suffix.toLowerCase())) {
			return trimmed.slice(0, -suffix.length) || null;
		}
	}
	const separatorIndex = trimmed.indexOf(".");
	return separatorIndex > 0 ? trimmed.slice(0, separatorIndex) : trimmed || null;
}

function getTailscaleOwner(status: TailscaleStatus, peer: TailscalePeerStatus): string | null {
	const userId = peer.AltSharerUserID ?? peer.UserID;
	if (userId === undefined || userId === null) return null;
	const profile = status.User?.[String(userId)];
	const login = profile?.LoginName;
	if (!login) return String(userId);
	const atIndex = login.indexOf("@");
	return atIndex >= 0 ? login.slice(0, atIndex + 1) : login;
}

function describeTailscalePeer(status: TailscaleStatus, peer: TailscalePeerStatus): string {
	const parts = [peer.Active ? "active" : peer.Online ? "online" : "offline"];
	if (peer.OS) parts.push(peer.OS);
	const owner = getTailscaleOwner(status, peer);
	if (owner) parts.push(owner);
	if (!peer.sshHostKeys?.length) parts.push("no advertised Tailscale SSH host key");
	return parts.join(" • ");
}

function tailscalePeerSortRank(peer: TailscalePeerStatus): number {
	const reachability = peer.Active ? 0 : peer.Online ? 1 : 2;
	const sshKeyPenalty = peer.sshHostKeys?.length ? 0 : 10;
	return sshKeyPenalty + reachability;
}

function shouldIncludeTailscalePeer(status: TailscaleStatus, peer: TailscalePeerStatus): boolean {
	if (peer.ShareeNode) return false;
	if (peer.ExitNodeOption && !peer.ExitNode && peer.DNSName?.endsWith("mullvad.ts.net.")) return false;
	return status.BackendState === "Running" || status.BackendState === "Starting";
}

function parseTailscaleStatusProfiles(): SshProfile[] {
	const result = spawnSync(TAILSCALE_COMMAND, ["status", "--json"], {
		encoding: "utf8",
		timeout: 1500,
		maxBuffer: 2 * 1024 * 1024,
	});
	if (result.status !== 0 || !result.stdout) return [];

	let status: TailscaleStatus;
	try {
		status = JSON.parse(result.stdout) as TailscaleStatus;
	} catch {
		return [];
	}
	const magicDNSSuffix = status.CurrentTailnet?.MagicDNSSuffix ?? status.MagicDNSSuffix;
	const profiles = new Map<string, SshProfile>();
	for (const peer of Object.values(status.Peer ?? {})) {
		if (!shouldIncludeTailscalePeer(status, peer)) continue;
		const dnsName = peer.DNSName ? stripTrailingDot(peer.DNSName) : undefined;
		const remote = dnsName ?? peer.HostName ?? peer.TailscaleIPs?.[0];
		if (!remote) continue;

		const baseName = dnsName ? basenameFromDNSName(dnsName, magicDNSSuffix) : peer.HostName;
		const displayName = baseName ?? remote;
		const name = `ts:${displayName}`;
		profiles.set(name, {
			name,
			remote,
			transport: "tailscale",
			description: describeTailscalePeer(status, peer),
			sortRank: tailscalePeerSortRank(peer),
		});
	}
	return Array.from(profiles.values()).sort((a, b) => (a.sortRank ?? 0) - (b.sortRank ?? 0) || a.name.localeCompare(b.name));
}

let cachedTailscaleProfiles: { time: number; profiles: SshProfile[] } | null = null;

export function parseTailscaleStatusProfilesCached(): SshProfile[] {
	const now = Date.now();
	if (cachedTailscaleProfiles && now - cachedTailscaleProfiles.time < 5000) return cachedTailscaleProfiles.profiles;
	const profiles = parseTailscaleStatusProfiles();
	cachedTailscaleProfiles = { time: now, profiles };
	return profiles;
}
