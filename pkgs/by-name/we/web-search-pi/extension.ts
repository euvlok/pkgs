import type { ExtensionAPI, ExtensionContext, MessageRenderer } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const STATUS_KEY = "codex-web-search";
const MESSAGE_TYPE = "codex-web-search";
const FLAG_DISABLE = "no-web-search";
const FLAG_CACHED = "web-search-cached";
const ENV_MODE = "PI_WEB_SEARCH";
const ENV_DEBUG = "PI_WEB_SEARCH_DEBUG";
const CLEAR_DELAY_MS = 1500;
const WEB_SEARCH_TOOL = "web_search";
const RESPONSES_URL_RE = /\/(?:codex\/)?responses(?:$|\?|\/)/;
const SSE_CONTENT_TYPE_RE = /\btext\/event-stream\b/i;

const RESPONSE_APIS = new Set(["openai-responses", "openai-codex-responses"]);
const OFF_MODES = new Set(["0", "false", "no", "off"]);
const ACTIONS = new Set(["search", "open_page", "find_in_page"]);
const DEBUG = ["1", "true", "yes"].includes(process.env[ENV_DEBUG]?.toLowerCase() ?? "");

const FLAGS = [
	[FLAG_DISABLE, { type: "boolean", default: false, description: "Disable Responses web_search injection" }],
	[FLAG_CACHED, { type: "boolean", default: false, description: "Use cached web search (external_web_access=false)" }],
] as const satisfies ReadonlyArray<readonly [string, Parameters<ExtensionAPI["registerFlag"]>[1]]>;

type Mode = "off" | "live" | "cached";
type Action = "search" | "open_page" | "find_in_page" | "other";
type Dict = Record<string, unknown>;
type FetchInput = Parameters<typeof fetch>[0];
type Snooper = (event: SseEvent) => void;

type ActionDetail = { actionType: Action; queries: readonly string[]; url: string; pattern: string };
type Detail = ActionDetail & { model: string; callId: string };
type WebSearchItem = { id: string; action: ActionDetail };
type SseEvent = { type: string; item?: WebSearchItem };

const EMPTY_DETAIL = {
	actionType: "other",
	queries: [],
	url: "",
	pattern: "",
	model: "",
	callId: "",
} as const satisfies Detail;

let activeSnooper: Snooper | null = null;
let fetchPatched = false;

const debug = (...args: readonly unknown[]): void => {
	if (DEBUG) console.error("[web-search]", ...args);
};

const isDict = (value: unknown): value is Dict => typeof value === "object" && value !== null;
const str = (value: unknown): string => {
	if (typeof value === "string") return value;
	return "";
};
const strings = (value: unknown): string[] => {
	if (!Array.isArray(value)) return [];
	return value.filter((item) => typeof item === "string" && item);
};
const array = (value: unknown): unknown[] => {
	if (Array.isArray(value)) return value;
	return [];
};
const dict = (value: unknown): Dict => {
	if (isDict(value)) return value;
	return {};
};
const unique = <T>(values: readonly T[]): T[] => [...new Set(values)];

const primary = ({ queries, url, pattern }: ActionDetail): string => queries[0] || url || pattern || "";
const summary = (detail: ActionDetail): string => primary(detail) || "(no detail)";
const errorMessage = (error: unknown): string => {
	if (error instanceof Error) return error.message;
	return String(error);
};

const modeFor = (pi: ExtensionAPI): Mode => {
	if (pi.getFlag(FLAG_DISABLE) === true) return "off";
	if (pi.getFlag(FLAG_CACHED) === true) return "cached";

	const raw = process.env[ENV_MODE]?.toLowerCase().trim();
	if (raw && OFF_MODES.has(raw)) return "off";
	if (raw === "cached") return "cached";
	return "live";
};

const supportsWebSearch = (ctx: ExtensionContext): boolean => {
	const api = ctx.model?.api;
	return typeof api === "string" && RESPONSE_APIS.has(api);
};

const isWebSearchTool = (tool: unknown): tool is Dict =>
	isDict(tool) && typeof tool.type === "string" && tool.type.startsWith(WEB_SEARCH_TOOL);

const addWebSearch = (payload: unknown, mode: Exclude<Mode, "off">): unknown | undefined => {
	if (!isDict(payload) || !("input" in payload)) return undefined;

	const tools = array(payload.tools);
	const existing = tools.findIndex(isWebSearchTool);
	const webSearch = { type: WEB_SEARCH_TOOL, external_web_access: mode === "live" };

	if (existing === -1) return { ...payload, tools: [...tools, webSearch] };
	if (mode !== "cached") return undefined;

	const current = tools[existing];
	if (!isWebSearchTool(current) || current.type !== WEB_SEARCH_TOOL || current.external_web_access === false) return undefined;

	return { ...payload, tools: tools.with(existing, { ...current, external_web_access: false }) };
};

const parseAction = (value: unknown): ActionDetail => {
	const action = dict(value);
	const rawType = str(action.type);
	let actionType: Action = "other";
	if (ACTIONS.has(rawType)) actionType = rawType as Action;

	return {
		actionType,
		queries: unique([str(action.query), ...strings(action.queries)].filter(Boolean)),
		url: str(action.url),
		pattern: str(action.pattern),
	};
};

const parseEvent = (value: unknown): SseEvent | undefined => {
	if (!isDict(value)) return undefined;
	const type = str(value.type);
	if (!type) return undefined;

	let item: WebSearchItem | undefined;
	if (isDict(value.item) && value.item.type === "web_search_call") {
		item = { id: str(value.item.id), action: parseAction(value.item.action) };
	}

	return { type, item };
};

const requestUrl = (input: FetchInput): string => {
	if (typeof input === "string") return input;
	if (input instanceof Request) return input.url;
	return input.toString();
};

const shouldSnoop = (url: string, response: Response, dispatch: Snooper | null): dispatch is Snooper => {
	const contentType = response.headers.get("content-type") ?? "";
	return (
		RESPONSES_URL_RE.test(url) &&
		response.ok &&
		response.body !== null &&
		dispatch !== null &&
		(contentType === "" || SSE_CONTENT_TYPE_RE.test(contentType))
	);
};

const dataFromFrame = (frame: string): string =>
	frame
		.replaceAll("\r\n", "\n")
		.replaceAll("\r", "\n")
		.split("\n")
		.filter((line) => line.startsWith("data:"))
		.map((line) => line.slice(5).trim())
		.join("\n")
		.trim();

async function parseSseStream(stream: ReadableStream<Uint8Array>, dispatch: Snooper): Promise<void> {
	const decoder = new TextDecoder();
	let buffer = "";

	const dispatchFrame = (frame: string): void => {
		const data = dataFromFrame(frame);
		if (!data || data === "[DONE]") return;

		try {
			const event = parseEvent(JSON.parse(data));
			if (event) dispatch(event);
		} catch (err) {
			debug("bad sse frame:", errorMessage(err));
		}
	};

	try {
		for await (const chunk of stream) {
			buffer += decoder.decode(chunk, { stream: true }).replaceAll("\r\n", "\n").replaceAll("\r", "\n");
			const frames = buffer.split("\n\n");
			buffer = frames.pop() ?? "";
			frames.forEach(dispatchFrame);
		}

		buffer += decoder.decode();
		if (buffer.trim()) dispatchFrame(buffer);
	} catch (err) {
		debug("snoop stream error:", errorMessage(err));
	}
}

const buildCell = (lines: readonly string[]): Box => {
	const box = new Box(1, 0);
	lines.forEach((line) => {
		box.addChild(new Text(line, 0, 0));
	});
	return box;
};

const renderLines = (
	detail: Detail,
	content: string | readonly unknown[],
	theme: Parameters<MessageRenderer<Detail>>[2],
): readonly string[] => {
	const sep = theme.fg("dim", "·");
	let model = "";
	if (detail.model) model = ` ${theme.fg("dim", `[${detail.model}]`)}`;
	const header = (label: string, suffix = "") => `${theme.fg("accent", label)}${model}${suffix}`;

	if (detail.actionType === "search") {
		let queries = detail.queries;
		if (queries.length === 0) queries = ["(no query)"];
		let count = "";
		if (queries.length > 1) count = ` ${theme.fg("dim", `(${queries.length} queries)`)}`;
		return [header("🌐 Searched", count), ...queries.map((query) => `  ${sep} ${query}`)];
	}

	if (detail.actionType === "open_page") return [`${header("🌐 Visited")} ${sep} ${detail.url || "(no url)"}`];

	if (detail.actionType === "find_in_page") {
		let found = detail.pattern || detail.url || "(no detail)";
		if (detail.pattern && detail.url) found = `'${detail.pattern}' in ${detail.url}`;
		return [`${header("🌐 Found in page")} ${sep} ${found}`];
	}

	let fallback = "(no detail)";
	if (typeof content === "string" && content) fallback = content;
	return [`${header("🌐 Web search")} ${sep} ${fallback}`];
};

const renderWebSearchMessage: MessageRenderer<Detail> = (message, _state, theme) =>
	buildCell(renderLines(message.details ?? EMPTY_DETAIL, message.content, theme));

const installFetchPatch = (): void => {
	if (fetchPatched) return;
	fetchPatched = true;

	const original = globalThis.fetch.bind(globalThis);
	globalThis.fetch = (async (input: FetchInput, init?: RequestInit) => {
		const response = await original(input, init);
		const dispatch = activeSnooper;
		const body = response.body;

		if (!body || !shouldSnoop(requestUrl(input), response, dispatch)) return response;

		const [clientStream, snoopStream] = body.tee();
		void parseSseStream(snoopStream, dispatch);
		return new Response(clientStream, { status: response.status, statusText: response.statusText, headers: response.headers });
	}) as typeof fetch;
};

export default function webSearchExtension(pi: ExtensionAPI): void {
	installFetchPatch();

	const completed = new Set<string>();
	const pending: Detail[] = [];
	let ctx: ExtensionContext | null = null;
	let clearTimer: ReturnType<typeof setTimeout> | null = null;

	const cancelClear = (): void => {
		if (clearTimer) clearTimeout(clearTimer);
		clearTimer = null;
	};

	const setStatus = (text: string): void => {
		debug("status:", text);
		if (!ctx?.hasUI) return;
		cancelClear();
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("accent", text));
		ctx.ui.setWorkingMessage(text);
	};

	const clearStatus = (): void => {
		cancelClear();
		if (!ctx?.hasUI) return;
		ctx.ui.setStatus(STATUS_KEY, undefined);
		ctx.ui.setWorkingMessage();
	};

	const clearSoon = (): void => {
		cancelClear();
		clearTimer = setTimeout(clearStatus, CLEAR_DELAY_MS);
	};

	const modelLabel = (): string => {
		if (!ctx?.model?.id) return "";
		return ` (${ctx.model.id})`;
	};
	const searching = (): void => setStatus(`🌐 Searching the web${modelLabel()}...`);
	const searched = (detail = ""): void => {
		let text = `✓ Searched${modelLabel()}`;
		if (detail) text += ` · ${detail}`;
		setStatus(text);
		clearSoon();
	};

	const flush = (): void => {
		if (!ctx?.hasUI || !ctx.isIdle() || pending.length === 0) return;
		pending.splice(0).forEach((detail) => {
			pi.sendMessage<Detail>(
				{ customType: MESSAGE_TYPE, content: summary(detail), display: true, details: detail },
				{ triggerTurn: false },
			);
		});
	};

	const enqueue = (item: WebSearchItem): void => {
		if (!ctx?.hasUI || (item.id && completed.has(item.id))) return;
		if (item.id) completed.add(item.id);
		pending.push({ ...item.action, model: ctx.model?.id ?? "", callId: item.id });
		flush();
	};

	const handlers: Record<string, (item?: WebSearchItem) => void> = {
		"response.output_item.added": (item) => item && searching(),
		"response.web_search_call.in_progress": searching,
		"response.web_search_call.searching": searching,
		"response.web_search_call.completed": () => searched(),
		"response.output_item.done": (item) => {
			if (!item) return;
			searched(primary(item.action));
			enqueue(item);
		},
	};

	const handleSseEvent = ({ type, item }: SseEvent): void => {
		if (type.startsWith("response.web_search") || handlers[type]) debug("sse:", type);
		handlers[type]?.(item);
	};

	const bind = (nextCtx: ExtensionContext, reset = false): void => {
		ctx = nextCtx;
		activeSnooper = handleSseEvent;
		if (!reset) return;
		completed.clear();
		pending.length = 0;
	};

	FLAGS.forEach(([name, options]) => {
		pi.registerFlag(name, options);
	});
	pi.registerMessageRenderer<Detail>(MESSAGE_TYPE, renderWebSearchMessage);

	pi.on("session_start", (_event, nextCtx) => bind(nextCtx, true));
	pi.on("session_tree", (_event, nextCtx) => bind(nextCtx, true));
	pi.on("model_select", (_event, nextCtx) => bind(nextCtx));

	pi.on("session_shutdown", () => {
		clearStatus();
		activeSnooper = null;
		ctx = null;
		pending.length = 0;
	});

	const endTurn = (_event: unknown, nextCtx: ExtensionContext): void => {
		bind(nextCtx);
		clearStatus();
		flush();
	};
	pi.on("message_end", endTurn);
	pi.on("turn_end", endTurn);

	pi.on("before_provider_request", (event, nextCtx) => {
		bind(nextCtx);
		const mode = modeFor(pi);
		if (mode === "off" || !supportsWebSearch(nextCtx)) return undefined;
		return addWebSearch(event.payload, mode);
	});
}
