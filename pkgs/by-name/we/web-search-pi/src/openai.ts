import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CHATGPT_CODEX_BASE_URL } from "./constants";
import type { Mode, WebSearchAction, WebSearchInput } from "./schema";
import { array, isDict, str, unique } from "./util";

type OpenAITextAnnotation = { type?: string; url?: string; title?: string };
type ParsedOpenAIResponse = { response: unknown; urls: string[]; actions: WebSearchAction[] };
type ResolvedOpenAIRequest = {
	provider: "openai-codex";
	model: string;
	headers: Record<string, string>;
	url: string;
};

const webSearchAction = (value: unknown): WebSearchAction | undefined => {
	if (!isDict(value)) return undefined;
	const type = str(value.type);
	if (!type) return undefined;
	const action: WebSearchAction = { type };
	const query = str(value.query);
	const url = str(value.url);
	const pattern = str(value.pattern);
	const queries = array(value.queries).map(str).filter(Boolean);
	if (query) action.query = query;
	if (queries.length > 0) action.queries = queries;
	if (url) action.url = url;
	if (pattern) action.pattern = pattern;
	return action;
};

const urlsInText = (text: string): string[] =>
	Array.from(text.matchAll(/https?:\/\/[^\s)\]}>"']+/g), (match) => match[0].replace(/[.,;:]+$/, ""));

const collectWebSearchMetadata = (value: unknown, urls: string[], actions: WebSearchAction[]): void => {
	if (Array.isArray(value)) {
		for (const item of value) collectWebSearchMetadata(item, urls, actions);
		return;
	}
	if (!isDict(value)) return;

	const url = str(value.url);
	if (url) urls.push(url);
	if (value.type === "web_search_call") {
		const action = webSearchAction(value.action);
		if (action) actions.push(action);
	}
	for (const item of Object.values(value)) collectWebSearchMetadata(item, urls, actions);
};

function parseOpenAIResponseText(text: string): ParsedOpenAIResponse {
	try {
		const response = text ? JSON.parse(text) : undefined;
		const urls: string[] = [];
		const actions: WebSearchAction[] = [];
		collectWebSearchMetadata(response, urls, actions);
		return { response, urls: unique(urls), actions };
	} catch {
		// Codex responses require streaming. Decode basic SSE frames and return the
		// completed response object when available, or synthesize output_text from
		// text deltas. While doing so, copy Codex's web_search_call action details
		// (search query, opened page URL, find-in-page URL) so the UI can show what
		// web sites/actions were actually used.
	}

	let completed: unknown;
	const deltas: string[] = [];
	const urls: string[] = [];
	const actions: WebSearchAction[] = [];
	const frames = text.replaceAll("\r\n", "\n").replaceAll("\r", "\n").split("\n\n");
	for (const frame of frames) {
		const data = frame
			.split("\n")
			.filter((line) => line.startsWith("data:"))
			.map((line) => line.slice(5).trim())
			.join("\n")
			.trim();
		if (!data || data === "[DONE]") continue;

		try {
			const event = JSON.parse(data);
			if (!isDict(event)) continue;
			collectWebSearchMetadata(event, urls, actions);
			if (event.type === "response.output_text.delta") {
				const delta = str(event.delta);
				if (delta) deltas.push(delta);
			} else if (event.type === "response.completed") {
				completed = event.response;
			}
		} catch {
			// Ignore malformed frames and keep parsing later frames.
		}
	}

	const response = completed ?? (deltas.length > 0 ? { output_text: deltas.join("") } : undefined);
	return { response, urls: unique(urls), actions };
}

function extractOpenAIText(response: unknown): { text: string; urls: string[]; responseId?: string } {
	const root = isDict(response) ? response : {};
	const outputText = str(root.output_text);
	const urls: string[] = [];
	const parts: string[] = [];

	if (outputText) parts.push(outputText);

	for (const item of array(root.output)) {
		if (!isDict(item)) continue;
		for (const content of array(item.content)) {
			if (!isDict(content)) continue;
			const text = str(content.text);
			if (text && !parts.includes(text)) parts.push(text);
			for (const annotation of array(content.annotations)) {
				if (!isDict(annotation)) continue;
				const url = str((annotation as OpenAITextAnnotation).url);
				if (url) urls.push(url);
			}
		}
	}

	const text = parts.join("\n\n").trim();
	return {
		text,
		urls: unique([...urls, ...urlsInText(text)]),
		responseId: str(root.id) || undefined,
	};
}

const codexResponsesUrlFor = (baseUrl?: string): string => {
	const url = (baseUrl?.trim() || CHATGPT_CODEX_BASE_URL).replace(/\/+$/, "");
	if (url.endsWith("/codex/responses")) return url;
	if (url.endsWith("/codex")) return `${url}/responses`;
	return `${url}/codex/responses`;
};

const decodeJwtPayload = (token: string): unknown => {
	const [, payload] = token.split(".");
	if (!payload) return undefined;
	const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
	const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
	return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
};

const accountIdFromAccessToken = (token: string): string | undefined => {
	try {
		const payload = decodeJwtPayload(token);
		if (!isDict(payload)) return undefined;
		const auth = payload["https://api.openai.com/auth"];
		if (!isDict(auth)) return undefined;
		return str(auth.chatgpt_account_id) || undefined;
	} catch {
		return undefined;
	}
};

async function resolveOpenAIRequest(ctx: ExtensionContext, model: string): Promise<ResolvedOpenAIRequest> {
	const codexModel =
		ctx.model?.provider === "openai-codex" && ctx.model.id === model ? ctx.model : ctx.modelRegistry.find("openai-codex", model);
	if (codexModel) {
		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(codexModel);
		if (!auth.ok) throw new Error(auth.error);
		const accessToken = auth.apiKey;
		if (!accessToken) throw new Error(`No ChatGPT account auth configured for OpenAI Codex model ${model}. Run /login for openai-codex.`);
		const accountId = accountIdFromAccessToken(accessToken);
		if (!accountId) throw new Error("OpenAI Codex auth token is missing a ChatGPT account id. Run /login again.");
		return {
			provider: "openai-codex",
			model: codexModel.id,
			url: codexResponsesUrlFor(codexModel.baseUrl),
			headers: {
				...(auth.headers ?? {}),
				authorization: `Bearer ${accessToken}`,
				"chatgpt-account-id": accountId,
				originator: "pi",
				"openai-beta": "responses=experimental",
			},
		};
	}

	throw new Error(`No OpenAI Codex model ${model} is available. Select an openai-codex model or set PI_WEB_SEARCH_MODEL to one.`);
}

export async function callOpenAIWebSearch(
	params: WebSearchInput,
	mode: Exclude<Mode, "off">,
	model: string,
	ctx: ExtensionContext,
	signal?: AbortSignal,
) {
	const request = await resolveOpenAIRequest(ctx, model);

	const response = await fetch(request.url, {
		method: "POST",
		headers: {
			...request.headers,
			"content-type": "application/json",
		},
		body: JSON.stringify({
			model: request.model,
			store: false,
			stream: true,
			instructions: "Use web search to answer the user's query. Return a concise answer and include source URLs for verification.",
			input: [{ role: "user", content: [{ type: "input_text", text: params.query }] }],
			tools: [{ type: "web_search", external_web_access: mode === "live" }],
			tool_choice: { type: "web_search" },
		}),
		signal,
	});

	const text = await response.text();
	const parsed = parseOpenAIResponseText(text);
	const json = parsed.response;

	if (!response.ok) {
		const message = isDict(json) && isDict(json.error) ? str(json.error.message) : text;
		throw new Error(`OpenAI web search failed (${response.status}): ${message || response.statusText}`);
	}

	const extracted = extractOpenAIText(json);
	return {
		...extracted,
		urls: unique([...extracted.urls, ...parsed.urls, ...parsed.actions.flatMap((action) => (action.url ? [action.url] : []))]),
		actions: parsed.actions,
		provider: request.provider,
		model: request.model,
	};
}
