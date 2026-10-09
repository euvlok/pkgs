#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert coreutils curl gh jq nix

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

repo="yt-dlp/yt-dlp"
commit="$(gh api "repos/$repo/commits/master")"
rev="$(jq -er .sha <<<"$commit")"
date="$(jq -er '.commit.committer.date[:10]' <<<"$commit")"
release_version="$(
  curl -fsSL "https://raw.githubusercontent.com/$repo/$rev/yt_dlp/version.py" |
    sed -nE "s/^__version__ = '([^']+)'.*/\1/p"
)"
if [[ ! "$release_version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "yt-dlp: could not determine the source version" >&2
  exit 1
fi

version="$release_version-unstable-$date"
if [[ "$(jq -r .rev source.json)" == "$rev" ]]; then
  echo "yt-dlp: already up to date ($version)"
  exit 0
fi

hash="$(nix flake prefetch --json "github:$repo/$rev" | jq -er .hash)"
source_tmp="$(mktemp ./source.json.XXXXXX)"
trap 'rm -f "$source_tmp"' EXIT
jq -n --arg version "$version" --arg rev "$rev" --arg srcHash "$hash" \
  '{version: $version, rev: $rev, srcHash: $srcHash}' >"$source_tmp"
mv "$source_tmp" source.json
echo "yt-dlp: updated to $version ($rev)"
