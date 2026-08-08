#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash cacert coreutils curl jq nixVersions.latest p7zip
# shellcheck shell=bash

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

repo="AppHouseKitchen/AlDente-Battery_Care_and_Monitoring"
api_url="https://api.github.com/repos/$repo/releases/latest"

if ! current="$(jq -er '.version | strings | select(test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))' source.json)"; then
  echo "aldente: source.json does not contain a valid version" >&2
  exit 1
fi

auth_header=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

release="$(
  curl -fsSL --compressed --max-time 60 --retry 3 --retry-delay 2 --retry-all-errors \
    "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$api_url"
)"

if ! latest="$(jq -er '.tag_name | strings | select(test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))' <<<"$release")"; then
  echo "aldente: GitHub returned an invalid release tag" >&2
  exit 1
fi

if ! asset_url="$(
  jq -er --arg version "$latest" '
    [
      .assets[]
      | select(
          .name == "AlDente.dmg"
          and .browser_download_url
            == "https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases/download/\($version)/AlDente.dmg"
        )
      | .browser_download_url
    ]
    | select(length == 1)
    | .[0]
  ' <<<"$release"
)"; then
  echo "aldente: release $latest does not contain exactly one expected AlDente.dmg asset" >&2
  exit 1
fi

if [[ "$latest" == "$current" ]]; then
  echo "aldente: already up to date ($current)"
  exit 0
fi

if [[ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]]; then
  echo "aldente: refusing to downgrade from $current to $latest" >&2
  exit 1
fi

echo "aldente: current=$current latest=$latest"
prefetch="$(nix --extra-experimental-features nix-command store prefetch-file --json "$asset_url")"
hash="$(jq -er '.hash' <<<"$prefetch")"
store_path="$(jq -er '.storePath' <<<"$prefetch")"

temp_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temp_dir"
}
trap cleanup EXIT

7zz x -y "-o$temp_dir" "$store_path" >/dev/null
info_plist="$temp_dir/AlDente.app/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  echo "aldente: downloaded DMG does not contain AlDente.app" >&2
  exit 1
fi

downloaded_version="$(
  sed -n '/<key>CFBundleShortVersionString<\/key>/{
    n
    s/.*<string>\([^<]*\)<\/string>.*/\1/p
    q
  }' "$info_plist"
)"

if [[ "$downloaded_version" != "$latest" ]]; then
  echo "aldente: release $latest contains app version $downloaded_version" >&2
  exit 1
fi

jq -n \
  --arg version "$latest" \
  --arg url "$asset_url" \
  --arg hash "$hash" \
  '{ version: $version, url: $url, hash: $hash }' > source.json.new
mv source.json.new source.json

echo "aldente: updated source.json to $latest"
