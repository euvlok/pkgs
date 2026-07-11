#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils curl gawk gnugrep jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

repo_owner="bethington"
repo_name="ghidra-mcp"
repo="${repo_owner}/${repo_name}"
branch="${GHIDRA_MCP_BRANCH:-main}"

auth_header=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

rev=$(
  curl -fsSL "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/git/ref/heads/${branch}" \
  | jq -r .object.sha
)

if [[ -z "$rev" || "$rev" == "null" ]]; then
  echo "no branch head found for $repo#$branch" >&2
  exit 1
fi

commit_date=$(
  curl -fsSL "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/commits/${rev}" \
  | jq -r .commit.committer.date
)
date="${commit_date%%T*}"

upstream_version=$(
  curl -fsSL "${auth_header[@]}" \
    "https://raw.githubusercontent.com/${repo}/${rev}/pyproject.toml" \
  | awk -F'"' '/^version = / {print $2; exit}'
)

if [[ -z "$upstream_version" ]]; then
  echo "could not determine upstream version from pyproject.toml at $rev" >&2
  exit 1
fi

version="${upstream_version}-unstable-${date}"
current_version=$(jq -r .version source.json)
current_rev=$(jq -r '.rev // empty' source.json)
nix_system=$(nix eval --impure --raw --expr builtins.currentSystem)
current_system_mvn_hash=$(jq -r --arg system "$nix_system" '.mavenHashes[$system] // empty' source.json)

if [[ "$current_rev" == "$rev" && "$current_version" == "$version" && -n "$current_system_mvn_hash" ]]; then
  echo "ghidra-mcp-headless already at ${branch}: ${version} (${rev})"
  exit 0
fi

if [[ "$current_rev" == "$rev" ]]; then
  src_hash=$(jq -r .srcHash source.json)
else
  src_hash=$(
    nix store prefetch-file --json --unpack \
      "https://github.com/${repo}/archive/${rev}.tar.gz" \
    | jq -r .hash
  )
fi

tmp_pkg=$(mktemp -d)
trap 'rm -rf "$tmp_pkg"' EXIT

jq -n \
  --arg version "$version" \
  --arg upstreamVersion "$upstream_version" \
  --arg rev "$rev" \
  --arg srcHash "$src_hash" \
  --arg system "$nix_system" \
  --arg mvnHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
  '{
    version: $version,
    upstreamVersion: $upstreamVersion,
    rev: $rev,
    srcHash: $srcHash,
    mavenHashes: {($system): $mvnHash}
  }' \
  >"$tmp_pkg/source.json"
cp package.nix update.sh "$tmp_pkg/"

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
  --arg upstreamVersion "$upstream_version" \
  --arg rev "$rev" \
  --arg srcHash "$src_hash" \
  --arg system "$nix_system" \
  --arg mvnHash "$mvn_hash" \
  --slurpfile current source.json \
  '{
    version: $version,
    upstreamVersion: $upstreamVersion,
    rev: $rev,
    srcHash: $srcHash,
    mavenHashes: (
      if ($current[0].rev // "") == $rev then
        ($current[0].mavenHashes // {})
      else
        {}
      end
      + {($system): $mvnHash}
    )
  }' \
  >"$tmp_source"
mv "$tmp_source" source.json

echo "ghidra-mcp-headless: $current_version -> $version (${rev})"
