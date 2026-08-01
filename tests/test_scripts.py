"""Focused regression tests for the repository's Python helpers."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import typer

import _common
import status
import update


class CommonHelpersTests(unittest.TestCase):
    def test_nix_eval_file_json_applies_string_arguments(self) -> None:
        nix_file = Path("scripts/nix/example.nix")
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout='{"answer":42}',
            stderr="",
        )

        with mock.patch.object(_common, "run", return_value=completed) as run:
            result = _common.nix_eval_file_json(
                nix_file,
                args={"plain": "value", "namesJson": '["one", "two"]'},
            )

        self.assertEqual(result, {"answer": 42})
        run.assert_called_once_with(
            [
                "nix-instantiate",
                "--eval",
                "--strict",
                "--json",
                "--impure",
                nix_file,
                "--argstr",
                "plain",
                "value",
                "--argstr",
                "namesJson",
                '["one", "two"]',
            ],
            cwd=_common.REPO_ROOT,
            capture=True,
            env_extra={"NIXPKGS_ALLOW_UNFREE": "1"},
            check=True,
        )

    def test_top_level_formal_args_ignore_comments_and_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            nix_file = Path(temp_dir) / "package.nix"
            nix_file.write_text(
                """
                {
                  alpha,
                  beta ? null, # an inline comment
                  gamma-delta,
                  ...
                }:
                { }
                """,
                encoding="utf-8",
            )

            self.assertEqual(
                _common.nix_top_level_formal_args(nix_file),
                {"alpha", "beta", "gamma-delta"},
            )

    def test_multiline_github_output_uses_a_safe_delimiter(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "output"
            with mock.patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}):
                _common.gha_output("packages", "one\nEOF\ntwo")

            self.assertEqual(
                output.read_text(encoding="utf-8"),
                "packages<<EOF_EOF\none\nEOF\ntwo\nEOF_EOF\n",
            )


class StatusTests(unittest.TestCase):
    def test_classify_all_statuses(self) -> None:
        cases = {
            ("<none>", "1", "1", None): "no-pin",
            ("1", "?", "1", None): "unknown",
            ("1", "", "1", None): "fork-only",
            ("1", "2", "1", None): "unknown",
            ("2", "1", "2", 1): "leading",
            ("1", "1", "1", 0): "synced",
            ("1", "2", "1", -1): "behind",
            ("1", "2", "2", -1): "behind (dormant)",
        }

        for arguments, expected in cases.items():
            with self.subTest(arguments=arguments):
                self.assertEqual(status.classify(*arguments), expected)


class UpdateSafetyTests(unittest.TestCase):
    def test_dirty_worktree_is_rejected_before_updates(self) -> None:
        with (
            mock.patch.object(update, "dirty_paths", return_value=[" M package.nix"]),
            mock.patch.object(update, "gha") as gha,
            self.assertRaises(typer.Exit) as raised,
        ):
            update.require_clean_worktree()

        self.assertEqual(raised.exception.exit_code, 1)
        gha.assert_called_once()

    def test_clean_worktree_is_accepted(self) -> None:
        with mock.patch.object(update, "dirty_paths", return_value=[]):
            update.require_clean_worktree()

    def test_failed_package_restore_removes_tracked_and_untracked_changes(self) -> None:
        package_dir = Path("pkgs/by-name/ex/example")
        completed = subprocess.CompletedProcess(args=[], returncode=0, stdout="", stderr="")

        with mock.patch.object(update, "run", return_value=completed) as run:
            update.restore_package(package_dir)

        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                [
                    "git",
                    "restore",
                    "--source=HEAD",
                    "--staged",
                    "--worktree",
                    "--",
                    package_dir,
                ],
                ["git", "clean", "-fd", "--", package_dir],
            ],
        )


if __name__ == "__main__":
    unittest.main()
