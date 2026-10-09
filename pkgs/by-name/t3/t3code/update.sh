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

repo="pingdotgg/t3code"
fake_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

stable_tag="$(
  gh release view --repo "$repo" --json tagName --jq '.tagName'
)"

nightly_tag="$(
  gh release list --repo "$repo" --limit 100 --json tagName,isPrerelease,publishedAt \
    --jq '[.[] | select(.isPrerelease and (.tagName | test("^v[0-9]+\\.[0-9]+\\.[0-9]+-nightly\\.")))] | sort_by(.publishedAt) | reverse | .[0].tagName'
)"

if [[ -z "$stable_tag" || "$stable_tag" == "null" ]]; then
  echo "Failed to resolve stable release tag" >&2
  exit 1
fi

if [[ -z "$nightly_tag" || "$nightly_tag" == "null" ]]; then
  echo "Failed to resolve nightly release tag" >&2
  exit 1
fi

prefetch_source() {
  local tag="$1"
  nix flake prefetch --json "github:${repo}/${tag}"
}

stable_prefetch="$(prefetch_source "$stable_tag")"
nightly_prefetch="$(prefetch_source "$nightly_tag")"

old_sources="$(cat sources.json)"
updated=false
sources_tmp="$(mktemp ./sources.json.XXXXXX)"
cleanup() {
  if [[ "$updated" == false ]]; then
    printf '%s\n' "$old_sources" >"$sources_tmp"
    mv "$sources_tmp" sources.json
  fi
  rm -f "$sources_tmp"
}
trap cleanup EXIT
stable_version="${stable_tag#v}"
stable_rev="$(jq -er '.locked.rev' <<<"$stable_prefetch")"
stable_src_hash="$(jq -r '.hash' <<<"$stable_prefetch")"
stable_node_modules_hash="$(jq -r '.stable.nodeModulesHash' <<<"$old_sources")"
nightly_version="${nightly_tag#v}"
nightly_rev="$(jq -er '.locked.rev' <<<"$nightly_prefetch")"
nightly_src_hash="$(jq -r '.hash' <<<"$nightly_prefetch")"
nightly_node_modules_hash="$(jq -r '.nightly.nodeModulesHash' <<<"$old_sources")"

write_sources() {
  local stable_nm_hash="$1"
  local nightly_nm_hash="$2"

  jq -n \
    --arg stable_version "$stable_version" \
    --arg stable_tag "$stable_tag" \
    --arg stable_rev "$stable_rev" \
    --arg stable_src_hash "$stable_src_hash" \
    --arg stable_node_modules_hash "$stable_nm_hash" \
    --arg nightly_version "$nightly_version" \
    --arg nightly_tag "$nightly_tag" \
    --arg nightly_rev "$nightly_rev" \
    --arg nightly_src_hash "$nightly_src_hash" \
    --arg nightly_node_modules_hash "$nightly_nm_hash" \
    '{
      stable: {
        version: $stable_version,
        tag: $stable_tag,
        rev: $stable_rev,
        srcHash: $stable_src_hash,
        nodeModulesHash: $stable_node_modules_hash
      },
      nightly: {
        version: $nightly_version,
        tag: $nightly_tag,
        rev: $nightly_rev,
        srcHash: $nightly_src_hash,
        nodeModulesHash: $nightly_node_modules_hash
      }
    }' >"$sources_tmp"
  mv "$sources_tmp" sources.json
}

refresh_pnpm_deps_hash() {
  local attr="$1"
  local label="$2"
  local system build_log hash

  system="$(nix eval --impure --raw --expr builtins.currentSystem)"
  echo "Refreshing ${label} pnpmDeps hash..." >&2

  build_log="$(
    nix build --impure --no-link --print-build-logs \
      ".#legacyPackages.${system}.${attr}.unwrapped.pnpmDeps" \
      --option sandbox true \
      2>&1 || true
  )"

  hash="$(awk '/got: +sha256-/ { print $2; exit }' <<<"$build_log")"
  if [[ -z "$hash" ]]; then
    printf '%s\n' "$build_log" >&2
    echo "Failed to determine ${label} pnpmDeps hash" >&2
    exit 1
  fi

  printf '%s' "$hash"
}

stable_changed="$(
  jq -r \
    --arg version "$stable_version" \
    --arg tag "$stable_tag" \
    --arg src_hash "$stable_src_hash" \
    '(.stable.version != $version) or (.stable.tag != $tag) or (.stable.srcHash != $src_hash)' \
    <<<"$old_sources"
)"
nightly_changed="$(
  jq -r \
    --arg version "$nightly_version" \
    --arg tag "$nightly_tag" \
    --arg src_hash "$nightly_src_hash" \
    '(.nightly.version != $version) or (.nightly.tag != $tag) or (.nightly.srcHash != $src_hash)' \
    <<<"$old_sources"
)"

write_sources "$stable_node_modules_hash" "$nightly_node_modules_hash"

if [[ "$stable_changed" == "true" ]]; then
  write_sources "$fake_hash" "$nightly_node_modules_hash"
  if ! new_hash="$(cd "$repo_root" && refresh_pnpm_deps_hash t3code stable)"; then
    write_sources "$stable_node_modules_hash" "$nightly_node_modules_hash"
    exit 1
  fi
  stable_node_modules_hash="$new_hash"
  write_sources "$stable_node_modules_hash" "$nightly_node_modules_hash"
fi

if [[ "$nightly_changed" == "true" ]]; then
  write_sources "$stable_node_modules_hash" "$fake_hash"
  if ! new_hash="$(cd "$repo_root" && refresh_pnpm_deps_hash t3code-nightly nightly)"; then
    write_sources "$stable_node_modules_hash" "$nightly_node_modules_hash"
    exit 1
  fi
  nightly_node_modules_hash="$new_hash"
  write_sources "$stable_node_modules_hash" "$nightly_node_modules_hash"
fi

updated=true
echo "Updated t3code stable to ${stable_tag}"
echo "Updated t3code nightly to ${nightly_tag}"
