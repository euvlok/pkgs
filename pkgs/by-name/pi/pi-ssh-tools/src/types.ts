export type SshTransport = "ssh" | "tailscale";

export type SshProfile = {
	name: string;
	remote: string;
	transport: SshTransport;
	cwd?: string;
	description?: string;
	sortRank?: number;
};

export type TailscalePeerStatus = {
	DNSName?: string;
	HostName?: string;
	OS?: string;
	UserID?: string | number;
	AltSharerUserID?: string | number;
	TailscaleIPs?: string[];
	Online?: boolean;
	Active?: boolean;
	ExitNode?: boolean;
	ExitNodeOption?: boolean;
	ShareeNode?: boolean;
	sshHostKeys?: string[];
};

export type TailscaleUserProfile = {
	LoginName?: string;
};

export type TailscaleStatus = {
	BackendState?: string;
	MagicDNSSuffix?: string;
	CurrentTailnet?: {
		MagicDNSSuffix?: string;
	};
	Peer?: Record<string, TailscalePeerStatus>;
	User?: Record<string, TailscaleUserProfile>;
};

export type ActiveSshTarget = {
	name: string;
	remote: string;
	transport: SshTransport;
	remoteCwd: string;
};

export type SshExecOptions = {
	stdin?: string | Buffer;
	signal?: AbortSignal;
	onStdoutData?: (data: Buffer) => void;
	onStderrData?: (data: Buffer) => void;
	timeoutSeconds?: number;
};
