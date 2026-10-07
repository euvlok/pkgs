#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash git nix

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
export EUPKGS_REPO_ROOT="${repo_root}"
exec nix run --accept-flake-config --impure "${repo_root}#update" -- pkg "$@"
