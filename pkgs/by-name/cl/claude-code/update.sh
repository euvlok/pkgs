#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils curl jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

BASE_URL="https://downloads.claude.ai/claude-code-releases"

VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"

source_tmp="$(mktemp ./source.json.XXXXXX)"
trap 'rm -f "$source_tmp"' EXIT
curl -fsSL "$BASE_URL/$VERSION/manifest.zst.json" --output "$source_tmp"
jq -e --arg version "$VERSION" '
  .version == $version
  and (.platforms | type == "object" and length > 0)
  and all(.platforms[]; .binary == "claude.zst" or .binary == "claude.exe.zst")
' "$source_tmp" >/dev/null
mv "$source_tmp" source.json
