import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { modeFor, modelFor } from "./src/config";
import { DEFAULT_MODEL, FLAG_CACHED, FLAG_DISABLE, FLAG_MODEL } from "./src/constants";
import { callOpenAIWebSearch } from "./src/openai";
import { resultBox } from "./src/render";
import { type WebSearchDetails, webSearchSchema } from "./src/schema";
import { debug, errorMessage } from "./src/util";

export default function webSearchExtension(pi: ExtensionAPI): void {
	pi.registerFlag(FLAG_DISABLE, { type: "boolean", default: false, description: "Disable the web_search tool" });
	pi.registerFlag(FLAG_CACHED, { type: "boolean", default: false, description: "Use cached OpenAI web search only" });
	pi.registerFlag(FLAG_MODEL, { type: "string", description: `OpenAI model for web_search (default: ${DEFAULT_MODEL})` });

	pi.registerTool<typeof webSearchSchema, WebSearchDetails>({
		name: "web_search",
		label: "Web Search",
		description: "Search the web using OpenAI's Responses API web_search tool and return an answer with source URLs.",
		promptSnippet: "Search the web for fresh or externally verifiable information",
		promptGuidelines: [
			"Use web_search when the user asks for latest/current information, explicit browsing, or facts likely to have changed.",
			"Use web_search instead of guessing for news, prices, laws, schedules, product specs, API docs, and other time-sensitive facts.",
			"When using web_search, cite or mention the source URLs returned by the tool in the final answer.",
		],
		parameters: webSearchSchema,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const mode = modeFor(pi);
			if (mode === "off") throw new Error("web_search is disabled by --no-web-search or PI_WEB_SEARCH=off.");

			const model = modelFor(pi, ctx);
			const setStatus = (text: string) => {
				if (!ctx.hasUI) return;
				ctx.ui.setStatus("web-search", ctx.ui.theme.fg("accent", text));
				ctx.ui.setWorkingMessage(text);
			};
			const clearStatus = () => {
				if (!ctx.hasUI) return;
				ctx.ui.setStatus("web-search", undefined);
				ctx.ui.setWorkingMessage();
			};

			setStatus(`🌐 Searching the web (${model})...`);
			try {
				const result = await callOpenAIWebSearch(params, mode, model, ctx, signal ?? ctx.signal);
				const answer = result.text || "No text result returned from OpenAI web search.";
				const details: WebSearchDetails = {
					query: params.query,
					provider: result.provider,
					model: result.model,
					mode,
					urls: result.urls,
					responseId: result.responseId,
				};
				debug("completed", details);
				return { content: [{ type: "text", text: answer }], details };
			} catch (error) {
				debug("failed", errorMessage(error));
				throw error;
			} finally {
				clearStatus();
			}
		},
		renderCall(args, theme) {
			const query = typeof args.query === "string" ? args.query : "...";
			return new Text(`${theme.fg("toolTitle", theme.bold("web_search"))} ${theme.fg("accent", query)}`, 0, 0);
		},
		renderResult(result, _options, theme) {
			const details = result.details;
			const lines = [
				`${theme.fg("success", "✓ Web search complete")} ${theme.fg("dim", `[${details.provider}/${details.model}, ${details.mode}]`)}`,
			];
			if (details.urls.length > 0) {
				lines.push(theme.fg("dim", `Sources: ${details.urls.slice(0, 5).join(" · ")}`));
			}
			return resultBox(lines);
		},
	});

	pi.on("session_start", (_event, ctx: ExtensionContext) => {
		if (modeFor(pi) === "off") {
			pi.setActiveTools(pi.getActiveTools().filter((name) => name !== "web_search"));
		}
		if (!ctx.hasUI) return;
		ctx.ui.setStatus("web-search", undefined);
	});
}
