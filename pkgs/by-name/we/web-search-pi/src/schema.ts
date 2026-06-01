import { type Static, Type } from "typebox";

export const webSearchSchema = Type.Object({
	query: Type.String({ description: "The web search query or precise research question." }),
});

export type Mode = "off" | "live" | "cached";
export type WebSearchInput = Static<typeof webSearchSchema>;
export type WebSearchDetails = {
	query: string;
	provider: string;
	model: string;
	mode: Exclude<Mode, "off">;
	urls: string[];
	responseId?: string;
};
