import {
	type Application,
	type CommandContext,
	type PartialApplicationConfiguration,
	run,
	text_en,
} from "@stricli/core";
import { ExitError } from "../process/process";

export function cliConfig(name: string): PartialApplicationConfiguration {
	return {
		name,
		scanner: {
			caseStyle: "allow-kebab-for-camel",
			allowArgumentEscapeSequence: true,
		},
		determineExitCode: (error) =>
			error instanceof ExitError ? error.exitCode : 1,
		localization: {
			text: {
				...text_en,
				formatException: (error) =>
					error instanceof Error ? error.message : String(error),
			},
		},
	};
}

export async function runCli(app: Application<CommandContext>): Promise<void> {
	await run(app, process.argv.slice(2), { process });
}
