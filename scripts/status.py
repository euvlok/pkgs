#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: [ ps.typer ps.rich ])" nix
"""Report how local package pins compare to nixpkgs master.

For every package under pkgs/by-name, compares its `upstreamVersion` pin to the
current nixpkgs master package version and to the version this flake evaluates.
Read-only.
"""

from __future__ import annotations

import json
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from _common import (
    BY_NAME,
    REPO_ROOT,
    nix_current_system,
    nix_eval_json,
    nix_string_attr,
    package_files,
)

NIXPKGS_MASTER = "github:NixOS/nixpkgs/master"

console = Console()

app = typer.Typer(add_completion=False, help=__doc__)


def flake_versions(flake_ref: str, system: str, names: list[str]) -> dict[str, str]:
    expr = f"""
      let
        flake = builtins.getFlake {json.dumps(flake_ref)};
        pkgs = builtins.getAttr {json.dumps(system)} flake.legacyPackages;
        names = builtins.fromJSON {json.dumps(json.dumps(names))};
        versionFor = name:
          if builtins.hasAttr name pkgs then
            let result = builtins.tryEval (toString ((builtins.getAttr name pkgs).version or ""));
            in if result.success then result.value else "?"
          else
            "";
      in
        builtins.listToAttrs (map (name: {{ inherit name; value = versionFor name; }}) names)
    """
    return {name: str(version) for name, version in nix_eval_json(expr).items()}


def upstream_pin(nix_file: Path) -> str:
    return nix_string_attr(nix_file, "upstreamVersion") or "<none>"


def compare_pins(rows: list[tuple[str, str, str]]) -> dict[str, int]:
    pairs = [
        {"name": name, "pin": pin, "upstream": upstream}
        for name, pin, upstream in rows
        if pin != "<none>" and upstream and upstream != "?"
    ]
    if not pairs:
        return {}

    expr = f"""
      let
        pairs = builtins.fromJSON {json.dumps(json.dumps(pairs))};
      in
        builtins.listToAttrs (map (p: {{
          name = p.name;
          value = builtins.compareVersions p.pin p.upstream;
        }}) pairs)
    """
    return {name: int(value) for name, value in nix_eval_json(expr).items()}


def classify(pin: str, upstream: str, effective: str, comparison: int | None) -> str:
    if pin == "<none>":
        return "no-pin"
    if upstream == "?":
        return "unknown"
    if not upstream:
        return "fork-only"
    if comparison is None:
        return "unknown"

    status = {
        1: "leading",
        0: "synced",
        -1: "behind",
    }[comparison]

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
    system = system or nix_current_system()
    pkg_files = package_files(by_name)
    package_names = [pkg_file.parent.name for pkg_file in pkg_files]

    with console.status("Evaluating package versions..."):
        upstream_versions = flake_versions(NIXPKGS_MASTER, system, package_names)
        effective_versions = flake_versions(f"path:{REPO_ROOT}", system, package_names)

    comparison_rows = []
    for pkg_file in pkg_files:
        name = pkg_file.parent.name
        pin = upstream_pin(pkg_file)
        upstream = upstream_versions.get(name, "")
        comparison_rows.append((name, pin, upstream))

    comparisons = compare_pins(comparison_rows)

    table = Table(title=f"Package Pin Status ({system})")
    table.add_column("Package", style="bold", no_wrap=True)
    table.add_column("Pin")
    table.add_column("Nixpkgs Master")
    table.add_column("Flake Effective")
    table.add_column("Status", no_wrap=True)

    status_styles = {
        "behind": "red",
        "fork-only": "yellow",
        "leading": "cyan",
        "no-pin": "dim",
        "synced": "green",
        "unknown": "magenta",
    }

    for name, pin, upstream in comparison_rows:
        effective = effective_versions.get(name, "?") or "?"
        status = classify(pin, upstream, effective, comparisons.get(name))
        base_status = status.removesuffix(" (dormant)")

        table.add_row(
            name,
            pin,
            upstream or "<not-in-nixpkgs>",
            effective,
            f"[{status_styles.get(base_status, '')}]{status}[/]",
        )

    console.print(table)


if __name__ == "__main__":
    app()
