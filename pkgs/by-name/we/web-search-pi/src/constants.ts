export const FLAG_DISABLE = "no-web-search";
export const FLAG_CACHED = "web-search-cached";
export const FLAG_MODEL = "web-search-model";

export const ENV_MODE = "PI_WEB_SEARCH";
export const ENV_MODEL = "PI_WEB_SEARCH_MODEL";
export const ENV_DEBUG = "PI_WEB_SEARCH_DEBUG";

export const DEFAULT_MODEL = "gpt-4.1-mini";
export const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
export const OFF_MODES = new Set(["0", "false", "no", "off"]);
export const DEBUG = ["1", "true", "yes"].includes(process.env[ENV_DEBUG]?.toLowerCase() ?? "");
