#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils curl jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

# This compatibility alias follows the same channel as nixpkgs' raycast
download_url="https://x.raycast-releases.com/download?platform=macos&architecture=arm64"
url="$(curl -fsSI --output /dev/null --write-out '%{redirect_url}' "$download_url")"
if [[ ! "$url" =~ ^https://x-r2\.raycast-releases\.com/Raycast_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)_[a-z0-9]+_arm64\.dmg$ ]]; then
  echo "raycast-beta: unexpected download URL $url" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
if [[ "$(jq -r '.version // empty' source.json)" == "$version" ]]; then
  echo "raycast-beta: already up to date ($version)"
  exit 0
fi
hash="$(nix store prefetch-file --json "$url" | jq -er .hash)"
source_tmp="$(mktemp ./source.json.XXXXXX)"
trap 'rm -f "$source_tmp"' EXIT
jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" \
  '{version: $version, url: $url, hash: $hash}' >"$source_tmp"
mv "$source_tmp" source.json
echo "raycast-beta: updated to $version"
