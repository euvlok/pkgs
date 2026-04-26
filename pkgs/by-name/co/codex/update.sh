#!/usr/bin/env nix
#!nix shell .#bash .#cacert .#coreutils .#curl .#gnugrep .#jq .#nix .#nix-prefetch-github --command bash

# Updates sources.json to the latest stable codex release.
# Pre-releases (alpha, beta, rc, "-unstable-" pins, etc.) are skipped: only
# tags matching ^rust-v(\d+\.\d+\.\d+)$ are considered.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

repo="openai/codex"
tag_regex='^rust-v[0-9]+\.[0-9]+\.[0-9]+$'

auth_header=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

latest_tag=$(
  curl -fsSL "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases?per_page=100" \
  | jq -r '.[] | select(.prerelease == false) | .tag_name' \
  | grep -E "$tag_regex" \
  | head -n1
)

if [[ -z "$latest_tag" ]]; then
  echo "no stable tag found for $repo" >&2
  exit 1
fi

version="${latest_tag#rust-v}"
current_version=$(jq -r .version sources.json)

if [[ "$current_version" == "$version" ]]; then
  echo "codex already at latest stable: $version"
  exit 0
fi

src_hash=$(nix-prefetch-github openai codex --rev "$latest_tag" --json | jq -r .hash)

# Fetch cargo vendor hash by building with a fake hash and reading the mismatch.
tmp_pkg=$(mktemp -d)
trap 'rm -rf "$tmp_pkg"' EXIT
cat >"$tmp_pkg/sources.json" <<EOF
{
  "version": "$version",
  "rev": "$latest_tag",
  "srcHash": "$src_hash",
  "cargoHash": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
}
EOF
cp package.nix ./*.patch "$tmp_pkg/"

build_log=$(NIXPKGS_ALLOW_UNFREE=1 nix build --impure --no-link --print-build-logs \
  --expr "with import <nixpkgs> {}; callPackage $tmp_pkg {}" 2>&1 || true)
cargo_hash=$(echo "$build_log" | awk '/got: +sha256-/ {print $2; exit}')

if [[ -z "$cargo_hash" ]]; then
  echo "failed to derive cargoHash; build log:" >&2
  echo "$build_log" >&2
  exit 1
fi

jq -n \
  --arg version "$version" \
  --arg rev "$latest_tag" \
  --arg srcHash "$src_hash" \
  --arg cargoHash "$cargo_hash" \
  '{version: $version, rev: $rev, srcHash: $srcHash, cargoHash: $cargoHash}' \
  >sources.json

echo "codex: $current_version -> $version"
