export const positive = (n: number) => (n > 0 ? n : undefined);
export const hasFormatArg = (args: readonly string[]) => args.some((a) => a === "--format" || a.startsWith("--format="));
export const oneLine = (text: string) =>
	text
		.replace(/[\r\n\t]/g, " ")
		.replace(/ +/g, " ")
		.trim();

export function parseStatuslineArgs(value: string): string[] {
	const input = value.trim();
	if (!input) return [];
	if (!input.startsWith("[")) return input.split(/\s+/).filter(Boolean);

	const parsed: unknown = JSON.parse(input);
	if (!Array.isArray(parsed) || !parsed.every((arg) => typeof arg === "string")) {
		throw new Error("statusline args JSON must be an array of strings");
	}
	return parsed;
}
