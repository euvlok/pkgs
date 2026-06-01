import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { DEFAULT_MODEL, ENV_MODE, ENV_MODEL, FLAG_CACHED, FLAG_DISABLE, FLAG_MODEL, OFF_MODES } from "./constants";
import type { Mode } from "./schema";

export const modeFor = (pi: ExtensionAPI): Mode => {
	if (pi.getFlag(FLAG_DISABLE) === true) return "off";
	if (pi.getFlag(FLAG_CACHED) === true) return "cached";

	const raw = process.env[ENV_MODE]?.toLowerCase().trim();
	if (raw && OFF_MODES.has(raw)) return "off";
	if (raw === "cached") return "cached";
	return "live";
};

export const modelFor = (pi: ExtensionAPI, ctx?: Pick<ExtensionContext, "model">): string => {
	const flag = pi.getFlag(FLAG_MODEL);
	if (typeof flag === "string" && flag.trim()) return flag.trim();
	const envModel = process.env[ENV_MODEL]?.trim();
	if (envModel) return envModel;
	if (ctx?.model?.provider === "openai-codex" && ctx.model.id) return ctx.model.id;
	return DEFAULT_MODEL;
};
