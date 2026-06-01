import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { OPENAI_RESPONSES_URL } from "./constants";
import type { Mode, WebSearchInput } from "./schema";
import { array, isDict, str, unique } from "./util";

type OpenAITextAnnotation = { type?: string; url?: string; title?: string };

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

	return {
		text: parts.join("\n\n").trim(),
		urls: unique(urls),
		responseId: str(root.id) || undefined,
	};
}

const responsesUrlFor = (baseUrl: string): string => {
	const url = baseUrl.replace(/\/$/, "");
	return url.endsWith("/responses") ? url : `${url}/responses`;
};

async function resolveOpenAIRequest(
	ctx: ExtensionContext,
	model: string,
): Promise<{ apiKey: string; headers: Record<string, string>; url: string }> {
	const registeredModel = ctx.modelRegistry.find("openai", model);
	if (registeredModel) {
		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(registeredModel);
		if (!auth.ok) throw new Error(auth.error);
		const apiKey = auth.apiKey ?? process.env.OPENAI_API_KEY;
		if (!apiKey) throw new Error(`No API key configured for OpenAI model ${model}.`);
		return { apiKey, headers: auth.headers ?? {}, url: responsesUrlFor(registeredModel.baseUrl) };
	}

	const apiKey = (await ctx.modelRegistry.getApiKeyForProvider("openai")) ?? process.env.OPENAI_API_KEY;
	if (!apiKey) throw new Error("No OpenAI API key configured. Run /login or set OPENAI_API_KEY.");
	return { apiKey, headers: {}, url: OPENAI_RESPONSES_URL };
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
			authorization: `Bearer ${request.apiKey}`,
		},
		body: JSON.stringify({
			model,
			input: params.query,
			tools: [{ type: "web_search", external_web_access: mode === "live" }],
			tool_choice: { type: "web_search" },
		}),
		signal,
	});

	const text = await response.text();
	let json: unknown;
	try {
		json = text ? JSON.parse(text) : undefined;
	} catch {
		json = undefined;
	}

	if (!response.ok) {
		const message = isDict(json) && isDict(json.error) ? str(json.error.message) : text;
		throw new Error(`OpenAI web search failed (${response.status}): ${message || response.statusText}`);
	}

	return extractOpenAIText(json);
}
