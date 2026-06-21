#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
UPDATE_FILE="$script_dir/../t3code/package.nix" exec "$script_dir/../t3code/update.sh" "$@"
