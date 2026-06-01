export const FLAG_COMMAND = "statusline-command";
export const FLAG_ARGS = "statusline-args";
export const STATUS_KEY = "agent-statusline";
export const DEFAULT_COMMAND = "agent-statusline";
export const REFRESH_DEBOUNCE_MS = 200;
export const SPAWN_TIMEOUT_MS = 3000;
export const IDLE_TICK_MS = 30_000;
export const PI_STATUSLINE_COMMAND = "PI_STATUSLINE_COMMAND";
export const PI_STATUSLINE_ARGS = "PI_STATUSLINE_ARGS";

export const STATUSLINE_FLAGS = [
	{ name: FLAG_COMMAND, description: `Statusline command to spawn (default: ${DEFAULT_COMMAND})` },
	{ name: FLAG_ARGS, description: "Extra args forwarded to the statusline command (whitespace-separated or JSON string array)" },
] as const;
