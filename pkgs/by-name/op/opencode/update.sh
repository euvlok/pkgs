#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils gh jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi
repo_root="$(cd ../../../.. && pwd -P)"
repo="anomalyco/opencode"
tag="$(gh release view --repo "$repo" --json tagName --jq .tagName)"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "opencode: invalid release tag $tag" >&2
  exit 1
fi
version="${tag#v}"
if [[ "$(jq -r .version source.json)" == "$version" ]]; then
  echo "opencode: already up to date ($version)"
  exit 0
fi

src_hash="$(nix flake prefetch --json "github:$repo/$tag" | jq -er .hash)"
old_source="$(cat source.json)"
updated=false
cleanup() {
  if [[ "$updated" == false ]]; then
    printf '%s\n' "$old_source" >source.json
  fi
}
trap cleanup EXIT

write_source() {
  jq -n --arg version "$version" --arg rev "$tag" --arg srcHash "$src_hash" \
    --arg nodeModulesHash "$1" \
    '{version: $version, rev: $rev, srcHash: $srcHash, nodeModulesHash: $nodeModulesHash}' \
    >source.json
}

write_source "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
system="$(nix eval --impure --raw --expr builtins.currentSystem)"
attr="$repo_root#legacyPackages.$system.opencode.node_modules"
package_version="$(nix eval --impure --raw "$repo_root#legacyPackages.$system.opencode.version")"

# Reuse nixpkgs' dependency hash only when it describes this exact release
if [[ "$package_version" == "$version" ]]; then
  hash="$(nix eval --impure --raw "$attr.outputHash")"
else
  hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
fi
if [[ "$hash" == "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" ]]; then
  nixpkgs_path="$(nix eval --impure --raw "$repo_root#legacyPackages.$system.path")"
  build_log="$(nix build --impure --no-link --print-build-logs --expr "
    let
      pkgs = import $nixpkgs_path { system = \"$system\"; };
      pinned = pkgs.callPackage $PWD/package.nix {
        opencode = pkgs.opencode.overrideAttrs { version = \"0.0.0\"; };
      };
    in pinned.node_modules
  " 2>&1 || true)"
  hash="$(awk '/got: +sha256-/ {print $2; exit}' <<<"$build_log")"
  if [[ -z "$hash" ]]; then
    printf '%s\n' "$build_log" >&2
    echo "opencode: could not determine the dependency hash" >&2
    exit 1
  fi
fi

write_source "$hash"
updated=true
echo "opencode: updated to $version"
