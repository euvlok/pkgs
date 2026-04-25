#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: [ ps.rich ps.tabulate ])"
"""Print a GitHub-flavored markdown table of every package under pkgs/by-name.

Invoked by a cog block in README.md when present. Run `cog -r README.md` to
refresh, or `cog --check README.md` to verify in CI.
"""

from __future__ import annotations

from rich.console import Console
from rich.progress import track
from tabulate import tabulate

from _common import BY_NAME, nix_current_system, nix_flake_attr, nix_string_attr, package_files
from _common import REPO_ROOT as ROOT

_err = Console(stderr=True)

SYSTEM = nix_current_system()


def rows() -> list[list[str]]:
    out = []
    for f in track(
        package_files(BY_NAME),
        description="Evaluating packages",
        console=_err,
    ):
        name = f.parent.name
        version = nix_flake_attr(name, "version", SYSTEM) or nix_string_attr(f, "version")
        desc = nix_flake_attr(name, "meta.description", SYSTEM) or nix_string_attr(f, "description")
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
