#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash coreutils gh jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

repo="cline/cline"
tag=$(
  gh release list --repo "$repo" --limit 100 --json tagName \
    --jq '.[].tagName' |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -V |
    tail -n 1
)

if [[ -z "$tag" ]]; then
  echo "cline-ai: no version release found" >&2
  exit 1
fi

version="${tag#v}"
url=$(
  gh release view "$tag" --repo "$repo" --json assets \
    --jq ".assets[] | select(.name == \"cline-${version}.vsix\") | .url"
)

if [[ -z "$url" ]]; then
  echo "cline-ai: no VSIX asset found for $tag" >&2
  exit 1
fi

hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" \
  '{version: $version, url: $url, hash: $hash}' >source.json

echo "cline-ai: updated to $version"
