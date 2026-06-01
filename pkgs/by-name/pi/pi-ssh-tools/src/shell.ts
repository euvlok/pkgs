export function shellQuote(value: string): string {
	return `'${value.replaceAll("'", `'"'"'`)}'`;
}

export function remotePathExpression(path: string): string {
	if (path === "~") return '"$HOME"';
	if (path.startsWith("~/")) return `"$HOME"/${shellQuote(path.slice(2))}`;
	return shellQuote(path);
}
