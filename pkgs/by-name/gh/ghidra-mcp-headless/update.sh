#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils curl gawk gnugrep jq nix nix-prefetch-github

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

repo_owner="bethington"
repo_name="ghidra-mcp"
repo="${repo_owner}/${repo_name}"
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'

auth_header=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

latest_tag=$(
  curl -fsSL "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/tags?per_page=100" \
  | jq -r '.[].name' \
  | grep -E "$tag_regex" \
  | sort -V \
  | tail -n1
)

if [[ -z "$latest_tag" ]]; then
  echo "no stable tag found for $repo" >&2
  exit 1
fi

version="${latest_tag#v}"
current_version=$(jq -r .version source.json)
nix_system=$(nix eval --impure --raw --expr builtins.currentSystem)
current_system_mvn_hash=$(jq -r --arg system "$nix_system" '.mavenHashes[$system] // empty' source.json)

if [[ "$current_version" == "$version" && -n "$current_system_mvn_hash" ]]; then
  echo "ghidra-mcp-headless already at latest stable: $version"
  exit 0
fi

if [[ "$current_version" == "$version" ]]; then
  src_hash=$(jq -r .srcHash source.json)
else
  src_hash=$(nix-prefetch-github "$repo_owner" "$repo_name" --rev "$latest_tag" --json | jq -r .hash)
fi

tmp_pkg=$(mktemp -d)
trap 'rm -rf "$tmp_pkg"' EXIT

jq -n \
  --arg version "$version" \
  --arg srcHash "$src_hash" \
  --arg system "$nix_system" \
  --arg mvnHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
  '{version: $version, srcHash: $srcHash, mavenHashes: {($system): $mvnHash}}' \
  >"$tmp_pkg/source.json"
cp package.nix bridge-auth-token.patch update.sh "$tmp_pkg/"

repo_root=$(realpath ../../../..)
build_log=$(nix build --impure --no-link --print-build-logs \
  --expr "with import $repo_root {}; callPackage $tmp_pkg/package.nix {}" 2>&1 || true)
mvn_hash=$(echo "$build_log" | awk '/got: +sha256-/ {print $2; exit}')

if [[ -z "$mvn_hash" ]]; then
  echo "failed to derive mvnHash; build log:" >&2
  echo "$build_log" >&2
  exit 1
fi

tmp_source=$(mktemp)
jq -n \
  --arg version "$version" \
  --arg srcHash "$src_hash" \
  --arg system "$nix_system" \
  --arg mvnHash "$mvn_hash" \
  --slurpfile current source.json \
  '{
    version: $version,
    srcHash: $srcHash,
    mavenHashes: (
      if $current[0].version == $version then
        ($current[0].mavenHashes // {})
      else
        {}
      end
      + {($system): $mvnHash}
    )
  }' \
  >"$tmp_source"
mv "$tmp_source" source.json

echo "ghidra-mcp-headless: $current_version -> $version"
