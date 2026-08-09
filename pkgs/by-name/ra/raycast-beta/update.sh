#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash cacert coreutils curl gnugrep gnused jq nixVersions.latest
# shellcheck shell=bash

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

release_page="https://www.raycast.com/new"
url_pattern='https://x-r2\.raycast-releases\.com/Raycast_Beta_[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+_[A-Za-z0-9]+_arm64\.dmg'

if ! current="$(jq -er '.version | strings | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))' source.json)"; then
  echo "raycast-beta: source.json does not contain a valid version" >&2
  exit 1
fi

if ! current_url="$(jq -er '.url | strings' source.json)"; then
  echo "raycast-beta: source.json does not contain a valid URL" >&2
  exit 1
fi

page="$(
  curl -fsSL --compressed --max-time 60 --retry 3 --retry-delay 2 --retry-all-errors \
    "$release_page"
)"

mapfile -t urls < <(grep -oE "$url_pattern" <<<"$page" | sort -u)
if (( ${#urls[@]} != 1 )); then
  echo "raycast-beta: expected exactly one beta download URL, found ${#urls[@]}" >&2
  exit 1
fi

latest_url="${urls[0]}"
latest="$(sed -E 's|.*/Raycast_Beta_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)_[^/]+_arm64\.dmg|\1|' <<<"$latest_url")"

if [[ "$latest" == "$current" && "$latest_url" == "$current_url" ]]; then
  echo "raycast-beta: already up to date ($current)"
  exit 0
fi

if [[ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]]; then
  echo "raycast-beta: refusing to downgrade from $current to $latest" >&2
  exit 1
fi

echo "raycast-beta: current=$current latest=$latest"
prefetch="$(nix --extra-experimental-features nix-command store prefetch-file --json "$latest_url")"
hash="$(jq -er '.hash' <<<"$prefetch")"

jq -n \
  --arg version "$latest" \
  --arg url "$latest_url" \
  --arg hash "$hash" \
  '{ version: $version, url: $url, hash: $hash }' > source.json.new
mv source.json.new source.json

echo "raycast-beta: updated source.json to $latest"
