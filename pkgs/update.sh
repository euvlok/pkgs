#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash "python3.withPackages (ps: [ ps.typer ])" nix-update git nix

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
exec python3 "${repo_root}/scripts/update.py" pkg "$@"
