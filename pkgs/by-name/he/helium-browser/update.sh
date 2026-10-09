#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils gh jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

source_tmp="$(mktemp ./source.json.XXXXXX)"
trap 'rm -f "$source_tmp"' EXIT
cp source.json "$source_tmp"

# Linux and macOS can publish stable releases at different times
for repo in helium-macos helium-linux; do
  release="$(gh api "repos/imputnet/$repo/releases/latest")"
  version="$(jq -er '.tag_name | select(test("^[0-9]+(\\.[0-9]+)+$"))' <<<"$release")"
  if [[ "$repo" == helium-macos ]]; then
    systems=(aarch64-darwin)
  else
    systems=(aarch64-linux x86_64-linux)
  fi

  for system in "${systems[@]}"; do
    case "$system" in
    aarch64-darwin) asset="helium_${version}_arm64-macos.dmg" ;;
    aarch64-linux) asset="helium-${version}-arm64_linux.tar.xz" ;;
    x86_64-linux) asset="helium-${version}-x86_64_linux.tar.xz" ;;
    esac
    url="$(jq -er --arg asset "$asset" '
      [.assets[] | select(.name == $asset) | .browser_download_url]
      | select(length == 1) | .[0]
    ' <<<"$release")"
    current_version="$(jq -r --arg system "$system" '.platforms[$system].version' source.json)"
    if [[ "$(printf '%s\n' "$current_version" "$version" | sort -V | tail -n1)" != "$version" ]]; then
      echo "helium-browser: refusing to downgrade $system from $current_version to $version" >&2
      exit 1
    fi
    if [[ "$(jq -r --arg system "$system" '.platforms[$system].url' source.json)" == "$url" ]]; then
      echo "helium-browser: $system already up to date ($version)"
      continue
    fi
    hash="$(nix store prefetch-file --json "$url" | jq -er .hash)"
    contents="$(jq --arg system "$system" --arg version "$version" --arg url "$url" --arg hash "$hash" \
      '.platforms[$system] = {version: $version, url: $url, hash: $hash}' "$source_tmp")"
    printf '%s\n' "$contents" >"$source_tmp"
    echo "helium-browser: $system updated to $version"
  done
done

mv "$source_tmp" source.json
