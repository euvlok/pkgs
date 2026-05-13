#!/usr/bin/env nix
#!nix shell .#bash .#cacert .#coreutils .#gh .#jq .#nix --command bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

repo="pingdotgg/t3code"

stable_tag="$(
  gh release view --repo "$repo" --json tagName --jq '.tagName'
)"

nightly_tag="$(
  gh release list --repo "$repo" --limit 100 --json tagName,isPrerelease,publishedAt \
    --jq '[.[] | select(.isPrerelease)] | sort_by(.publishedAt) | reverse | .[0].tagName'
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

stable_release="$(
  gh release view "$stable_tag" --repo "$repo" --json tagName,targetCommitish
)"
nightly_release="$(
  gh release view "$nightly_tag" --repo "$repo" --json tagName,targetCommitish
)"

stable_prefetch="$(prefetch_source "$stable_tag")"
nightly_prefetch="$(prefetch_source "$nightly_tag")"

jq -n \
  --arg stable_version "${stable_tag#v}" \
  --arg stable_tag "$stable_tag" \
  --arg stable_rev "$(jq -r '.targetCommitish' <<<"$stable_release")" \
  --arg stable_src_hash "$(jq -r '.hash' <<<"$stable_prefetch")" \
  --arg stable_node_modules_hash "$(jq -r '.stable.nodeModulesHash' sources.json)" \
  --arg nightly_version "${nightly_tag#v}" \
  --arg nightly_tag "$nightly_tag" \
  --arg nightly_rev "$(jq -r '.targetCommitish' <<<"$nightly_release")" \
  --arg nightly_src_hash "$(jq -r '.hash' <<<"$nightly_prefetch")" \
  --arg nightly_node_modules_hash "$(jq -r '.nightly.nodeModulesHash' sources.json)" \
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
  }' > sources.json

echo "Updated t3code stable to ${stable_tag}"
echo "Updated t3code nightly to ${nightly_tag}"
echo "Note: if dependencies changed, refresh nodeModulesHash by building the node_modules passthru and copying Nix's reported hash."
