import { Box, Text } from "@earendil-works/pi-tui";

export const resultBox = (lines: readonly string[]): Box => {
	const box = new Box(1, 0);
	for (const line of lines) box.addChild(new Text(line, 0, 0));
	return box;
};
