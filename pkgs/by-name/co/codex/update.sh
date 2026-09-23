#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils curl gnugrep jq nix

# Updates source.json to the latest Codex alpha release.

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

repo="openai/codex"
tag_regex='^rust-v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$'

auth_header=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

latest_tag=$(
  curl -fsSL "${auth_header[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases?per_page=100" \
  | jq -r '.[] | select(.prerelease == true) | .tag_name' \
  | grep -E "$tag_regex" \
  | sort -V \
  | tail -n1
)

if [[ -z "$latest_tag" ]]; then
  echo "no alpha tag found for $repo" >&2
  exit 1
fi

version="${latest_tag#rust-v}"
current_version=$(jq -r .version source.json)

if [[ "$current_version" == "$version" ]]; then
  echo "codex already at latest alpha: $version"
  exit 0
fi

src_hash=$(nix hash convert --hash-algo sha256 --from nix32 \
  "$(nix-prefetch-url --unpack "https://github.com/openai/codex/archive/refs/tags/$latest_tag.tar.gz")")

# Fetch only the Cargo vendor derivation, without compiling Codex.
tmp_pkg=$(mktemp -d)
trap 'rm -rf "$tmp_pkg"' EXIT
cat >"$tmp_pkg/vendor.nix" <<'EOF'
{ version, rev, srcHash }:
let
  pkgs = import <nixpkgs> { };
  src = pkgs.fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    inherit rev;
    hash = srcHash;
  };
in
pkgs.rustPlatform.fetchCargoVendor {
  name = "codex-${version}-vendor";
  inherit src;
  sourceRoot = "${src.name}/codex-rs";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
}
EOF

build_log=$(NIXPKGS_ALLOW_UNFREE=1 nix build --impure --no-link --print-build-logs \
  --file "$tmp_pkg/vendor.nix" \
  --argstr version "$version" \
  --argstr rev "$latest_tag" \
  --argstr srcHash "$src_hash" 2>&1 || true)
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
  >source.json

echo "codex: $current_version -> $version"
