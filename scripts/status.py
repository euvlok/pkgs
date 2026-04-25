#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: [ ps.typer ps.rich ])" gh nix
"""Report how local package pins compare to nixpkgs master.

For every package under pkgs/by-name, compares its `upstreamVersion` pin to the
current nixpkgs master package version and to the version this flake evaluates.
Read-only.
"""

from __future__ import annotations

import base64
import json
import re
from pathlib import Path

import typer

from _common import REPO_ROOT, nix_eval, run

BY_NAME = REPO_ROOT / "pkgs" / "by-name"
UPSTREAM_VERSION_RE = re.compile(r'^\s*upstreamVersion\s*=\s*"([^"]+)"\s*;', re.M)
VERSION_RE = re.compile(r'^\s*version\s*=\s*"([^"]+)"\s*;', re.M)

app = typer.Typer(add_completion=False, help=__doc__)


def github_content(path: str) -> str:
    r = run(
        ["gh", "api", f"repos/NixOS/nixpkgs/contents/{path}", "--jq", ".content"],
        capture=True,
    )
    if r.returncode != 0:
        return ""

    payload = r.stdout.strip()
    if not payload or payload == "null":
        return ""

    try:
        return base64.b64decode(payload).decode()
    except ValueError:
        return ""


def fetch_nixpkgs_version(shard: str, name: str) -> str:
    package_nix = github_content(f"pkgs/by-name/{shard}/{name}/package.nix")
    if package_nix:
        match = VERSION_RE.search(package_nix)
        if match:
            return match.group(1)

    manifest = github_content(f"pkgs/by-name/{shard}/{name}/manifest.json")
    if manifest:
        try:
            return str(json.loads(manifest).get("version") or "")
        except json.JSONDecodeError:
            return ""

    return ""


def upstream_pin(nix_file: Path) -> str:
    match = UPSTREAM_VERSION_RE.search(nix_file.read_text())
    return match.group(1) if match else "<none>"


def compare_versions(a: str, b: str) -> int:
    expr = f"toString (builtins.compareVersions {json.dumps(a)} {json.dumps(b)})"
    value = nix_eval(expr, check=True)
    return int(value)


def effective_version(system: str, name: str) -> str:
    value = run(
        ["nix", "eval", "--impure", "--raw", f".#legacyPackages.{system}.{name}.version"],
        cwd=REPO_ROOT,
        capture=True,
        env_extra={"NIXPKGS_ALLOW_UNFREE": "1"},
    )
    return value.stdout.strip() if value.returncode == 0 else "?"


def classify(pin: str, upstream: str, effective: str) -> str:
    if pin == "<none>":
        return "no-pin"
    if not upstream:
        return "fork-only"

    status = {
        1: "leading",
        0: "synced",
        -1: "behind",
    }[compare_versions(pin, upstream)]

    if effective != pin and effective != "?":
        status += " (dormant)"

    return status


@app.command()
def main(
    by_name: Path = typer.Option(BY_NAME, "--by-name", help="Root of the by-name package tree."),
    system: str = typer.Option(
        "",
        "--system",
        help="System to evaluate. Defaults to builtins.currentSystem.",
    ),
) -> None:
    """Print package pin status."""
    system = system or nix_eval("builtins.currentSystem", check=True)

    print(f"{'PACKAGE':<18} {'PIN':<32} {'NIXPKGS MASTER':<22} {'FLAKE EFFECTIVE':<22} STATUS")
    print(f"{'-------':<18} {'---':<32} {'--------------':<22} {'---------------':<22} ------")

    for pkg_file in sorted(by_name.glob("*/*/package.nix")):
        pkg_dir = pkg_file.parent
        name = pkg_dir.name
        shard = pkg_dir.parent.name
        pin = upstream_pin(pkg_file)
        effective = effective_version(system, name)
        upstream = fetch_nixpkgs_version(shard, name)
        status = classify(pin, upstream, effective)

        print(f"{name:<18} {pin:<32} {upstream or '<not-in-nixpkgs>':<22} {effective:<22} {status}")


if __name__ == "__main__":
    app()
