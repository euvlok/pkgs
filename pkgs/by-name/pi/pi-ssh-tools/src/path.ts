import { extname } from "node:path";

export function inferImageMimeType(path: string): string | null {
	switch (extname(path).toLowerCase()) {
		case ".jpg":
		case ".jpeg":
			return "image/jpeg";
		case ".png":
			return "image/png";
		case ".gif":
			return "image/gif";
		case ".webp":
			return "image/webp";
		default:
			return null;
	}
}

export function stripTrailingDot(value: string): string {
	return value.endsWith(".") ? value.slice(0, -1) : value;
}
