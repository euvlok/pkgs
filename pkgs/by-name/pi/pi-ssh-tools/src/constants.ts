import { homedir } from "node:os";
import { join } from "node:path";

export const SSH_STATUS_KEY = "ssh-tools";
export const SSH_TOOL_NAMES = ["ssh_read", "ssh_ls", "ssh_find", "ssh_write", "ssh_edit", "ssh_bash"] as const;
export const SSH_CONFIG_PATH = join(homedir(), ".ssh", "config");
export const SSH_COMMAND = "ssh";
export const TAILSCALE_COMMAND = "tailscale";
