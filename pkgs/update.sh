#!/usr/bin/env nix-shell
#!nix-shell -i bash -p "python3.withPackages (ps: [ ps.typer ps.rich ])" nix-update git nix
# shellcheck shell=bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
exec python3 "${repo_root}/scripts/update.py" pkg "$@"
