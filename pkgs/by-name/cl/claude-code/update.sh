#!/usr/bin/env nix
#!nix shell .#bash .#cacert .#coreutils .#curl .#jq .#nix --command bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"

# Upstream manifest format: { version, platforms: { "darwin-arm64": { checksum, ... }, ... } }
# Our manifest format: { version, platforms: { "<system>": { url, hash } } } — same as nix store hashes.
upstream=$(curl -fsSL "$BASE_URL/$VERSION/manifest.json")

declare -A platform_map=(
  [aarch64-darwin]=darwin-arm64
  [x86_64-darwin]=darwin-x64
  [aarch64-linux]=linux-arm64
  [x86_64-linux]=linux-x64
)

jq_filter='{version: $version, platforms: $platforms}'

platforms_json='{}'
for system in aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux; do
  upstream_key="${platform_map[$system]}"
  checksum=$(jq -r --arg k "$upstream_key" '.platforms[$k].checksum' <<<"$upstream")
  if [[ -z "$checksum" || "$checksum" == "null" ]]; then
    echo "Missing checksum for $upstream_key in upstream manifest" >&2
    exit 1
  fi
  sri=$(nix hash convert --hash-algo sha256 --to sri "$checksum")
  platforms_json=$(jq \
    --arg system "$system" \
    --arg url "$upstream_key/claude" \
    --arg hash "$sri" \
    '. + {($system): {url: $url, hash: $hash}}' <<<"$platforms_json")
done

jq -n \
  --arg version "$VERSION" \
  --argjson platforms "$platforms_json" \
  "$jq_filter" >manifest.json
