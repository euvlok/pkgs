#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: [ ps.typer ])" nix-update git nix
"""Update by-name nix packages.

Subcommands:
  pkg <path>  Update a single package.nix. Dispatches on passthru.updateScript:
                string -> build as shell-script-bin and execute
                path   -> execute the file directly
                absent -> fall back to nix-update
  all         Walk pkgs/by-name, update each fetchable derivation, verify with
              `nix build`, and commit `<pkg>: bump` per package. Reverts the
              working tree on any failure.
"""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Annotated, Literal

import typer

from _common import (
    REPO_ROOT,
    gha,
    gha_group,
    gha_output,
    gha_summary,
    nix_current_system,
    nix_eval,
    package_files,
    pkg_wrapper,
    run,
)

app = typer.Typer(add_completion=False, help=__doc__)

_failure_annotation_kind = "error"


def log_error(msg: str, file: str | None = None) -> None:
    gha(_failure_annotation_kind, msg, file)


@contextlib.contextmanager
def tolerated_failure_annotations():
    """Downgrade per-package failures while the all-packages updater keeps going."""
    global _failure_annotation_kind
    previous = _failure_annotation_kind
    _failure_annotation_kind = "warning"
    try:
        yield
    finally:
        _failure_annotation_kind = previous


def log_info(msg: str) -> None:
    gha("debug", msg)


def log_notice(msg: str, file: str | None = None) -> None:
    gha("notice", msg, file)


@dataclass(slots=True, frozen=True)
class Metadata:
    owner: str
    repo: str
    update_script_kind: Literal["", "string", "path"]

    @property
    def slug(self) -> str:
        return f"{self.owner}/{self.repo}"


def extract_metadata(nix_file: Path) -> Metadata:
    log_info(f"Checking metadata for '{nix_file}'...")
    with pkg_wrapper(nix_file) as wrapper:
        update_type = nix_eval(
            f"let p = import {wrapper}; us = p.passthru.updateScript or null; "
            f'in if us == null then "" else builtins.typeOf us'
        )
        kind: Literal["", "string", "path"] = (
            "string" if update_type == "string" else "path" if update_type == "path" else ""
        )

        owner = repo = ""
        if kind:
            log_info(f"Found custom passthru.updateScript ({kind}) in package")
            homepage = nix_eval(f'(import {wrapper}).meta.homepage or ""')
            m = re.match(r"https://github\.com/([^/]+)/([^/]+)", homepage)
            if m:
                owner, repo = m.group(1), m.group(2)
            else:
                owner = repo = "unknown"
        else:
            if update_type:
                log_info(
                    f"passthru.updateScript has type '{update_type}', falling back to nix-update"
                )
            owner = nix_eval(f"(import {wrapper}).src.owner")
            repo = nix_eval(f"(import {wrapper}).src.repo")
            if not owner or not repo:
                log_error(
                    f"Could not extract owner/repo from '{nix_file}'. "
                    "Make sure that file contains 'owner' and 'repo' attributes.",
                    file=str(nix_file),
                )
                raise typer.Exit(1)

    log_info(f"Found repository: {owner}/{repo}")
    return Metadata(owner=owner, repo=repo, update_script_kind=kind)


def run_path_update_script(nix_file: Path, wrapper: Path) -> None:
    script_path = nix_eval(f"toString (import {wrapper} {{}}).pkg.passthru.updateScript")
    if not script_path or not Path(script_path).is_file():
        log_error(f"Could not resolve path updateScript for '{nix_file}'")
        raise typer.Exit(1)
    with contextlib.suppress(OSError):
        os.chmod(script_path, 0o755)
    if run([script_path], env_extra={"UPDATE_FILE": str(nix_file)}).returncode != 0:
        log_error("updateScript failed", file=str(nix_file))
        raise typer.Exit(1)


def run_string_update_script(nix_file: Path, meta: Metadata) -> None:
    log_info("Executing updateScript...")
    print()

    pkg_name = nix_file.parent.name
    temp_root = os.environ.get("TEMP_DIR")
    with tempfile.TemporaryDirectory(prefix=f"{pkg_name}-update-", dir=temp_root) as temp_dir:
        out_link = Path(temp_dir) / "result"
        with pkg_wrapper(nix_file) as wrapper:
            wrapper.write_text(
                "{ pkgs ? import <nixpkgs> {} }:\n"
                "let\n"
                f"  pkg = pkgs.callPackage {nix_file} {{}};\n"
                f'in pkgs.writeShellScriptBin "{pkg_name}-update-script" '
                "(builtins.readFile pkg.passthru.updateScript)\n",
                encoding="utf-8",
            )
            build = run(
                [
                    "nix",
                    "build",
                    "--impure",
                    "--file",
                    wrapper,
                    "--out-link",
                    out_link,
                    "--print-build-logs",
                ]
            )
            if build.returncode != 0:
                log_error(f"Failed to build updateScript for {meta.slug}", file=str(nix_file))
                raise typer.Exit(1)

            bin_dir = out_link / "bin"
            binary = next(
                (path for path in bin_dir.iterdir() if path.is_file() and os.access(path, os.X_OK)),
                None,
            )
            if binary is None:
                log_error(f"No executable found in {bin_dir}")
                raise typer.Exit(1)

            if run([binary], env_extra={"UPDATE_FILE": str(nix_file)}).returncode != 0:
                log_error("updateScript failed")
                raise typer.Exit(1)


def dirty_paths(path: Path) -> list[str]:
    result = run(
        ["git", "status", "--porcelain", "--untracked-files=all", "--", path],
        cwd=REPO_ROOT,
        capture=True,
        check=True,
    )
    return result.stdout.splitlines()


def require_clean_worktree() -> None:
    dirty = dirty_paths(REPO_ROOT)
    if not dirty:
        return

    gha(
        "error",
        "Refusing to update a dirty worktree; commit or stash these paths first:\n"
        + "\n".join(dirty),
    )
    raise typer.Exit(1)


def restore_package(pkg_dir: Path) -> None:
    """Restore a package after a failed update; callers guarantee a clean starting tree."""
    run(
        ["git", "restore", "--source=HEAD", "--staged", "--worktree", "--", pkg_dir],
        cwd=REPO_ROOT,
        check=True,
    )
    run(["git", "clean", "-fd", "--", pkg_dir], cwd=REPO_ROOT, check=True)


def pkg_has_changes(pkg_dir: Path) -> bool:
    return bool(dirty_paths(pkg_dir))


def commit_pkg(pkg_name: str, pkg_dir: Path) -> bool:
    run(["git", "add", "--", pkg_dir], cwd=REPO_ROOT, check=True)
    if run(["git", "diff", "--staged", "--quiet", "--", pkg_dir], cwd=REPO_ROOT).returncode == 0:
        return False
    run(["git", "commit", "-m", f"{pkg_name}: bump", "--", pkg_dir], cwd=REPO_ROOT, check=True)
    return True


@cache
def nix_update_bin() -> str:
    if path := shutil.which("nix-update"):
        return path

    system = nix_current_system()
    r = run(
        [
            "nix",
            "build",
            "--impure",
            "--no-link",
            "--print-out-paths",
            f".#legacyPackages.{system}.nix-update",
        ],
        cwd=REPO_ROOT,
        capture=True,
        env_extra={"NIXPKGS_ALLOW_UNFREE": "1"},
    )
    if r.returncode != 0:
        log_error("nix-update is not on PATH and could not be built from the flake")
        raise typer.Exit(1)

    out_path = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""
    candidate = Path(out_path) / "bin" / "nix-update"
    if not candidate.is_file():
        log_error(f"nix-update executable not found at {candidate}")
        raise typer.Exit(1)

    return str(candidate)


def run_nix_update(
    nix_file: Path,
    wrapper: Path,
    version: str,
    meta: Metadata,
    subpackages: list[str],
) -> None:
    log_info(f"Executing nix-update with version '{version}'...")
    print()
    subpackage_args = [arg for subpackage in subpackages for arg in ("--subpackage", subpackage)]
    r = run(
        [
            nix_update_bin(),
            f"--version={version}",
            *subpackage_args,
            "-f",
            wrapper,
            "--override-filename",
            nix_file,
            "pkg",
        ]
    )
    if r.returncode != 0:
        log_error(f"nix-update failed for {meta.slug}", file=str(nix_file))
        raise typer.Exit(1)


def write_pkg_summary(nix_file: Path, meta: Metadata, version: str) -> None:
    parts = [
        f"### {nix_file.parent.name}\n",
        f"- Repository: `{meta.slug}`\n",
    ]
    if not meta.update_script_kind:
        parts.append(f"- Version: `{version}`\n")
    parts.append(f"- File: `{nix_file}`\n")
    gha_summary("".join(parts))


def update_one(
    nix_file: Path,
    version: str = "branch",
    subpackages: list[str] | None = None,
) -> None:
    abs_nix_file = nix_file.resolve()
    subpackages = subpackages or []
    with gha_group(f"Package update: {nix_file}"):
        meta = extract_metadata(abs_nix_file)

        log_info(f"Updating '{abs_nix_file}' for {meta.slug}...")
        log_notice(f"Updating {meta.slug}", file=str(abs_nix_file))

        if meta.update_script_kind == "string":
            run_string_update_script(abs_nix_file, meta)
        else:
            with pkg_wrapper(abs_nix_file, rec=True) as wrapper:
                if meta.update_script_kind == "path":
                    run_path_update_script(abs_nix_file, wrapper)
                else:
                    run_nix_update(abs_nix_file, wrapper, version, meta, subpackages)

        write_pkg_summary(abs_nix_file, meta, version)
        log_notice("Package update completed successfully!")


def is_fetchable_derivation(pkg_path: Path) -> bool:
    name = pkg_path.parent.name
    system = nix_current_system()
    r = run(
        [
            "nix",
            "eval",
            "--impure",
            "--raw",
            f".#legacyPackages.{system}.{name}.type",
        ],
        cwd=REPO_ROOT,
        capture=True,
        env_extra={"NIXPKGS_ALLOW_UNFREE": "1"},
    )
    if r.returncode != 0 or r.stdout.strip() != "derivation":
        return False

    r = run(
        [
            "nix",
            "eval",
            "--impure",
            "--raw",
            f".#legacyPackages.{system}.{name}.src.drvPath",
        ],
        cwd=REPO_ROOT,
        capture=True,
        env_extra={"NIXPKGS_ALLOW_UNFREE": "1"},
    )
    return r.returncode == 0 and bool(r.stdout.strip())


def build_pkg(pkg_path: Path) -> bool:
    name = pkg_path.parent.name
    system = nix_current_system()
    return (
        run(
            [
                "nix",
                "build",
                "--impure",
                "--no-link",
                "--print-build-logs",
                "--option",
                "sandbox",
                "true",
                f".#legacyPackages.{system}.{name}",
            ],
            cwd=REPO_ROOT,
            env_extra={"NIXPKGS_ALLOW_UNFREE": "1"},
        ).returncode
        == 0
    )


@app.command("pkg")
def cmd_pkg(
    nix_file: Annotated[
        Path,
        typer.Argument(
            exists=True,
            dir_okay=False,
            readable=True,
            help="Path to a package.nix under pkgs/by-name.",
        ),
    ],
    version: Annotated[
        str,
        typer.Option(
            "--version",
            help="Version argument for nix-update (ignored when an updateScript is present).",
        ),
    ] = "branch",
    subpackages: Annotated[
        list[str] | None,
        typer.Option(
            "--subpackage",
            help="Child derivation hash to bump with nix-update. May be passed multiple times.",
        ),
    ] = None,
) -> None:
    """Update a single package."""
    update_one(nix_file, version, subpackages)


@app.command("all")
def cmd_all(
    by_name: Annotated[
        Path,
        typer.Option("--by-name", help="Root of the by-name package tree."),
    ] = REPO_ROOT / "pkgs" / "by-name",
    version: Annotated[
        str,
        typer.Option("--version", help="Version argument for nix-update."),
    ] = "branch",
) -> None:
    """Walk pkgs/by-name, update each fetchable derivation, and commit per-package bumps."""
    if not shutil.which("nix") or not shutil.which("git"):
        gha("error", "nix and git must be on PATH")
        raise typer.Exit(1)

    require_clean_worktree()
    pkg_files = package_files(by_name)
    updated: list[str] = []

    for nixfile in pkg_files:
        pkg_dir = nixfile.parent
        name = pkg_dir.name

        with gha_group(f"Updating {name}"):
            if not is_fetchable_derivation(nixfile):
                gha("notice", f"Skipping {name} (not a fetchable derivation)", file=str(nixfile))
                continue

            try:
                with tolerated_failure_annotations():
                    update_one(nixfile, version)
            except typer.Exit:
                gha("warning", f"Update failed for {name}", file=str(nixfile))
                restore_package(pkg_dir)
                continue

            if not pkg_has_changes(pkg_dir):
                gha("notice", f"No changes for {name}", file=str(nixfile))
                continue

            if not build_pkg(nixfile):
                gha("warning", f"Build failed for {name} after update", file=str(nixfile))
                restore_package(pkg_dir)
                continue

            if commit_pkg(name, pkg_dir):
                updated.append(f"{name}|{pkg_dir}")
                gha("notice", f"Updated {name} successfully and build verified")

    gha_output("has_changes", "true" if updated else "false")
    gha_output("updated_packages", "\n".join(updated))
    if updated:
        gha_summary("### Updated packages\n```\n" + "\n".join(updated) + "\n```\n")
    else:
        gha_summary("### No changes detected\nAll packages are up to date.\n")


if __name__ == "__main__":
    app()
