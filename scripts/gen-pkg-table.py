#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: [ ps.rich ps.tabulate ])"
"""Print a GitHub-flavored markdown table of every package under pkgs/by-name.

Run `nix run .#gen-pkg-table` from the repository root.
"""

from __future__ import annotations

import json
from typing import TypedDict

from rich.console import Console
from tabulate import tabulate

from _common import (
    BY_NAME,
    NIX_HELPERS,
    nix_current_system,
    nix_eval_file_json,
    nix_string_attr,
    package_files,
)
from _common import REPO_ROOT as ROOT

_err = Console(stderr=True)


class PackageMetadata(TypedDict):
    version: str
    description: str


def flake_package_metadata(system: str, names: list[str]) -> dict[str, PackageMetadata]:
    """Evaluate all package metadata in a single Nix process."""
    return nix_eval_file_json(
        NIX_HELPERS / "package-metadata.nix",
        args={
            "localFlakeRef": f"path:{ROOT}",
            "system": system,
            "namesJson": json.dumps(names),
        },
    )


def rows() -> list[list[str]]:
    pkg_files = package_files(BY_NAME)
    names = [pkg_file.parent.name for pkg_file in pkg_files]
    with _err.status("Evaluating packages..."):
        metadata = flake_package_metadata(nix_current_system(), names)

    out: list[list[str]] = []
    for f in pkg_files:
        name = f.parent.name
        package = metadata.get(name, {"version": "", "description": ""})
        version = package["version"] or nix_string_attr(f, "version")
        desc = package["description"] or nix_string_attr(f, "description")
        link = f.parent.relative_to(ROOT).as_posix()
        out.append([f"[`{name}`]({link})", f"`{version or '?'}`", desc])
    return out


if __name__ == "__main__":
    print(
        tabulate(
            rows(),
            headers=["Package", "Version", "Description"],
            tablefmt="github",
        )
    )
