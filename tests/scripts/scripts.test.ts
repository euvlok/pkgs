import { afterEach, describe, expect, mock, spyOn, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { number, object } from "valibot";
import { ghaOutput } from "../../scripts/github-actions/github-actions";
import { nixEvalFileJson } from "../../scripts/nix/nix";
import { nixTopLevelFormalArgs } from "../../scripts/nix/syntax";
import { ExitError } from "../../scripts/process/process";
import { REPO_ROOT } from "../../scripts/repository/repository";
import { classify } from "../../scripts/status/versions";
import {
	requireCleanWorktree,
	restorePackage,
} from "../../scripts/update/worktree";

const completed = Bun.spawnSync([process.execPath, "-e", ""]);
const tempDirs: string[] = [];
function tempDir(): string {
	const dir = mkdtempSync(join(tmpdir(), "eupkgs-test-"));
	tempDirs.push(dir);
	return dir;
}

afterEach(() => {
	mock.restore();
	for (const dir of tempDirs.splice(0))
		rmSync(dir, { recursive: true, force: true });
});

describe("Common helpers", () => {
	test("Nix file evaluation applies string arguments", () => {
		const nixFile = "scripts/nix/example.nix";
		const spawn = spyOn(Bun, "spawnSync").mockReturnValue({
			...completed,
			exitCode: 0,
			stdout: Buffer.from('{"answer":42}'),
			stderr: Buffer.alloc(0),
		});
		expect(
			nixEvalFileJson(
				nixFile,
				{ plain: "value", namesJson: '["one", "two"]' },
				object({ answer: number() }),
			),
		).toEqual({ answer: 42 });
		expect(spawn).toHaveBeenCalledTimes(1);
		expect(spawn).toHaveBeenCalledWith(
			[
				"nix-instantiate",
				"--eval",
				"--strict",
				"--json",
				"--impure",
				nixFile,
				"--argstr",
				"plain",
				"value",
				"--argstr",
				"namesJson",
				'["one", "two"]',
			],
			{
				cwd: REPO_ROOT,
				stdin: "inherit",
				stdout: "pipe",
				stderr: "pipe",
				env: { ...process.env, NIXPKGS_ALLOW_UNFREE: "1" },
			},
		);
	});

	test("Top-level formal arguments ignore comments and defaults", () => {
		const file = join(tempDir(), "package.nix");
		writeFileSync(
			file,
			`{
  alpha,
  beta ? null, # an inline comment
  gamma-delta,
  ...
}: { }\n`,
		);
		expect(nixTopLevelFormalArgs(file)).toEqual(
			new Set(["alpha", "beta", "gamma-delta"]),
		);
	});

	test("Multiline GitHub output uses a safe delimiter", () => {
		const output = join(tempDir(), "output");
		writeFileSync(output, "");
		const previous = process.env.GITHUB_OUTPUT;
		process.env.GITHUB_OUTPUT = output;
		try {
			ghaOutput("packages", "one\nEOF\ntwo");
			const content = readFileSync(output, "utf8");
			const delimiter = content.match(/^packages<<([^\n]+)\n/)?.[1];
			expect(delimiter).toBeDefined();
			expect("one\nEOF\ntwo").not.toContain(delimiter ?? "");
			expect(content).toBe(
				`packages<<${delimiter}\none\nEOF\ntwo\n${delimiter}\n`,
			);
		} finally {
			if (previous === undefined) delete process.env.GITHUB_OUTPUT;
			else process.env.GITHUB_OUTPUT = previous;
		}
	});
});

describe("Status", () => {
	test("Classifies all statuses", () => {
		const cases: [string, string, string, number | undefined, string][] = [
			["<none>", "1", "1", undefined, "no-pin"],
			["1", "?", "1", undefined, "unknown"],
			["1", "", "1", undefined, "fork-only"],
			["1", "2", "1", undefined, "unknown"],
			["2", "1", "2", 1, "leading"],
			["1", "1", "1", 0, "synced"],
			["1", "2", "1", -1, "behind"],
			["1", "2", "2", -1, "behind (dormant)"],
		];
		for (const [pin, upstream, effective, comparison, expected] of cases)
			expect(classify(pin, upstream, effective, comparison)).toBe(expected);
	});
});

describe("Update safety", () => {
	test("Rejects a dirty worktree before updating", () => {
		spyOn(Bun, "spawnSync").mockReturnValue({
			...completed,
			exitCode: 0,
			stdout: Buffer.from(" M package.nix\n"),
			stderr: Buffer.alloc(0),
		});
		const output = spyOn(process.stdout, "write").mockImplementation(
			() => true,
		);
		expect(requireCleanWorktree).toThrow(ExitError);
		expect(output).toHaveBeenCalledTimes(1);
		expect(output.mock.calls[0]?.[0]).toContain(
			"::error::Refusing to update a dirty worktree",
		);
	});

	test("Accepts a clean worktree", () => {
		spyOn(Bun, "spawnSync").mockReturnValue({
			...completed,
			exitCode: 0,
			stdout: Buffer.alloc(0),
			stderr: Buffer.alloc(0),
		});
		expect(requireCleanWorktree).not.toThrow();
	});

	test("Restoring a failed package removes tracked and untracked changes", () => {
		const dir = "pkgs/by-name/ex/example";
		const spawn = spyOn(Bun, "spawnSync").mockReturnValue({
			...completed,
			exitCode: 0,
			stdout: Buffer.alloc(0),
			stderr: Buffer.alloc(0),
		});
		restorePackage(dir);
		expect(spawn.mock.calls.map((call) => call[0])).toEqual([
			["git", "restore", "--source=HEAD", "--staged", "--worktree", "--", dir],
			["git", "clean", "-fd", "--", dir],
		]);
	});
});
