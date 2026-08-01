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
from typing import Annotated, TypedDict

import typer
from rich.console import Console
from rich.table import Table
from rich.text import Text

from _common import (
    BY_NAME,
    NIX_HELPERS,
    REPO_ROOT,
    nix_current_system,
    nix_eval_file_json,
    nix_eval_json,
    nix_string_attr,
    package_files,
)

NIXPKGS_MASTER = "github:NixOS/nixpkgs/master"

console = Console()


class PackageState(TypedDict):
    effective: str
    pin: str
    upstream: str


def package_states(system: str, names: list[str]) -> dict[str, PackageState]:
    """Evaluate upstream and local package state in a single Nix process."""
    return nix_eval_file_json(
        NIX_HELPERS / "package-states.nix",
        args={
            "upstreamFlakeRef": NIXPKGS_MASTER,
            "localFlakeRef": f"path:{REPO_ROOT}",
            "system": system,
            "namesJson": json.dumps(names),
        },
    )


def textual_upstream_pin(nix_file: Path) -> str:
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


def main(
    by_name: Annotated[
        Path,
        typer.Option("--by-name", help="Root of the by-name package tree."),
    ] = BY_NAME,
    system: Annotated[
        str,
        typer.Option("--system", help="System to evaluate. Defaults to builtins.currentSystem."),
    ] = "",
) -> None:
    """Print package pin status."""
    system = system or nix_current_system()
    pkg_files = package_files(by_name)
    package_names = [pkg_file.parent.name for pkg_file in pkg_files]

    with console.status("Evaluating package versions..."):
        states = package_states(system, package_names)

    comparison_rows = []
    for pkg_file in pkg_files:
        name = pkg_file.parent.name
        state = states.get(name, {"effective": "?", "pin": "", "upstream": ""})
        pin = state["pin"] or textual_upstream_pin(pkg_file)
        upstream = state["upstream"]
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
        effective = states.get(name, {"effective": "?", "pin": "", "upstream": ""})["effective"]
        status = classify(pin, upstream, effective, comparisons.get(name))
        base_status = status.removesuffix(" (dormant)")

        table.add_row(
            name,
            pin,
            upstream or "<not-in-nixpkgs>",
            effective,
            Text(status, style=status_styles.get(base_status, "")),
        )

    console.print(table)


if __name__ == "__main__":
    typer.run(main)
