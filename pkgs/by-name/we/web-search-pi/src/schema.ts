import { type Static, Type } from "typebox";

export const webSearchSchema = Type.Object({
	query: Type.String({ description: "The web search query or precise research question." }),
});

export type Mode = "off" | "live" | "cached";
export type WebSearchInput = Static<typeof webSearchSchema>;
export type WebSearchAction = {
	type: string;
	query?: string;
	queries?: string[];
	url?: string;
	pattern?: string;
};

export type WebSearchDetails = {
	query: string;
	provider: string;
	model: string;
	mode: Exclude<Mode, "off">;
	urls: string[];
	actions: WebSearchAction[];
	responseId?: string;
};
