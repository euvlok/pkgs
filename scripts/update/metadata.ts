import { array, type InferOutput, object, string } from "valibot";
import { nixEvalJson } from "../nix/nix";
import { nixPath } from "../nix/syntax";

const metadataSchema = object({
	command: array(string()),
	attrPath: string(),
	name: string(),
	pname: string(),
	version: string(),
	homepage: string(),
});
export type Metadata = InferOutput<typeof metadataSchema>;

export function slug(meta: Metadata): string {
	return (
		meta.homepage.match(/^https:\/\/github\.com\/([^/]+\/[^/]+)/)?.[1] ??
		meta.pname
	);
}

export function extractMetadata(wrapper: string): Metadata {
	return nixEvalJson(`(import ${nixPath(wrapper)} {}).update`, metadataSchema);
}
