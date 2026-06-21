#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
UPDATE_FILE="$script_dir/../ghidra-mcp-headless/package.nix" exec "$script_dir/../ghidra-mcp-headless/update.sh" "$@"
