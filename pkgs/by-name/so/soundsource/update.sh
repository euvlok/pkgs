#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash cacert coreutils curl gnused jq nixVersions.latest openssl
# shellcheck shell=bash

set -euo pipefail

if [[ -n "${UPDATE_FILE:-}" ]]; then
  cd "$(dirname "$UPDATE_FILE")"
else
  cd "$(dirname "${BASH_SOURCE[0]}")"
fi

download_url="https://cdn.rogueamoeba.com/soundsource/download/SoundSource.zip"
release_notes_url="https://rogueamoeba.com/support/releasenotes/?product=SoundSource"
cdx_url="https://web.archive.org/cdx/search/cdx"

if ! current="$(jq -er '.version | strings | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' source.json)"; then
  echo "soundsource: source.json does not contain a valid version" >&2
  exit 1
fi

latest="$(
  curl -fsSL --compressed --max-time 60 --retry 3 --retry-delay 2 --retry-all-errors \
    "$release_notes_url" |
    sed -nE 's/.*>([0-9]+\.[0-9]+\.[0-9]+)<.*/\1/p' |
    sed -n '1p'
)"

if [[ -z "$latest" ]]; then
  echo "soundsource: could not determine the current version from $release_notes_url" >&2
  exit 1
fi

if [[ "$latest" == "$current" ]]; then
  echo "soundsource: already up to date ($current)"
  exit 0
fi

if [[ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]]; then
  echo "soundsource: refusing to downgrade from $current to $latest" >&2
  exit 1
fi

temp_dir="$(mktemp -d)"
source_tmp=""
cleanup() {
  rm -rf -- "$temp_dir"
  if [[ -n "$source_tmp" ]]; then
    rm -f -- "$source_tmp"
  fi
}
trap cleanup EXIT

bundle_version() {
  sed -n '/<key>CFBundleShortVersionString<\/key>/{
    n
    s/.*<string>\([^<]*\)<\/string>.*/\1/p
    q
  }' "$1/Contents/Info.plist"
}

nix_prefetch() {
  nix --extra-experimental-features nix-command store prefetch-file --json "$@"
}

prefetch_archive() {
  local archive_url="$1"
  local prefetch store_path downloaded_version archive_hash

  if ! prefetch="$(nix_prefetch --unpack "$archive_url")"; then
    return 1
  fi

  store_path="$(jq -r '.storePath' <<<"$prefetch")"
  downloaded_version="$(bundle_version "$store_path")"
  archive_hash="$(jq -r '.hash' <<<"$prefetch")"

  if [[ "$downloaded_version" != "$latest" ]]; then
    echo "soundsource: $archive_url contains $downloaded_version, not $latest" >&2
    return 1
  fi
  if [[ "$archive_hash" != "$live_hash" ]]; then
    echo "soundsource: archived ZIP differs from the verified rolling download" >&2
    return 1
  fi

  snapshot_url="$archive_url"
  snapshot_hash="$archive_hash"
}

echo "soundsource: current=$current latest=$latest"
echo "soundsource: verifying the rolling upstream download"

live_raw_prefetch="$(nix_prefetch "$download_url")"
live_zip_path="$(jq -r '.storePath' <<<"$live_raw_prefetch")"
live_digest="$(openssl dgst -sha1 -binary "$live_zip_path" | base32 | tr -d '\n=')"
live_prefetch="$(nix_prefetch --unpack "file://$live_zip_path")"
live_store_path="$(jq -r '.storePath' <<<"$live_prefetch")"
live_hash="$(jq -r '.hash' <<<"$live_prefetch")"
downloaded_version="$(bundle_version "$live_store_path")"

if [[ "$downloaded_version" != "$latest" ]]; then
  echo "soundsource: release notes report $latest but the download contains $downloaded_version" >&2
  exit 1
fi

snapshot_url=""
snapshot_hash=""

# Reuse a successful capture of the exact rolling ZIP when another updater has
# already saved this release. CDX digests are RFC 4648 base32-encoded SHA-1.
if ! cdx_response="$(
  curl -fsSL --max-time 60 --retry 3 --retry-delay 2 --retry-all-errors --get "$cdx_url" \
    --data-urlencode "url=$download_url" \
    --data-urlencode 'output=json' \
    --data-urlencode 'fl=timestamp,digest' \
    --data-urlencode 'filter=statuscode:200' \
    --data-urlencode "filter=digest:^${live_digest}$" \
    --data-urlencode 'limit=-1'
)"; then
  echo "soundsource: could not query Wayback Machine captures" >&2
  exit 1
fi

if ! jq -e --arg digest "$live_digest" '
  type == "array"
  and (
    length == 0
    or (
      .[0] == ["timestamp", "digest"]
      and all(.[1:][]; (
        type == "array"
        and length == 2
        and (.[0] | test("^[0-9]{14}$"))
        and .[1] == $digest
      ))
    )
  )
' >/dev/null <<<"$cdx_response"; then
  echo "soundsource: Wayback Machine returned an unexpected CDX response" >&2
  exit 1
fi

latest_capture="$(jq -r 'if length > 1 then .[-1][0] else empty end' <<<"$cdx_response")"

if [[ -n "$latest_capture" ]]; then
  candidate="https://web.archive.org/web/${latest_capture}id_/$download_url"
  echo "soundsource: verifying matching capture $latest_capture"
  if ! prefetch_archive "$candidate"; then
    echo "soundsource: matching capture exists but could not be verified" >&2
    exit 1
  fi
fi

submit_capture() {
  local submit_html job_id status_json status timestamp poll_finished attempt poll
  submit_html="$temp_dir/submit.html"

  for attempt in 1 2 3; do
    echo "soundsource: submitting capture to Wayback Machine (attempt $attempt/3)"
    if ! curl -fsSL --max-time 90 \
      --data-urlencode "url=$download_url" \
      "https://web.archive.org/save/$download_url" \
      -o "$submit_html"; then
      continue
    fi

    job_id="$(
      sed -nE 's/.*spn\.watchJob\("([^"]+)".*/\1/p' "$submit_html" |
        sed -n '1p'
    )"
    if [[ ! "$job_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "soundsource: Wayback response did not contain a Save Page Now job ID" >&2
      continue
    fi

    poll_finished="false"
    for ((poll = 1; poll <= 100; poll++)); do
      status_json="$(
        curl -fsSL --max-time 60 "https://web.archive.org/save/status/$job_id" ||
          true
      )"
      status="$(jq -r '.status // empty' <<<"$status_json" 2>/dev/null || true)"

      case "$status" in
        success)
          timestamp="$(jq -r '.timestamp' <<<"$status_json")"
          if [[ ! "$timestamp" =~ ^[0-9]{14}$ ]]; then
            echo "soundsource: capture succeeded without a valid timestamp" >&2
            poll_finished="true"
            break
          fi
          snapshot_url="https://web.archive.org/web/${timestamp}id_/$download_url"
          return 0
          ;;
        error)
          echo "soundsource: capture failed: $(jq -r '.message // "unknown error"' <<<"$status_json")" >&2
          poll_finished="true"
          break
          ;;
        *) sleep 6 ;;
      esac
    done

    if [[ "$poll_finished" == "false" ]]; then
      echo "soundsource: timed out waiting for Save Page Now job $job_id" >&2
    fi
    if ((attempt < 3)); then
      sleep 6
    fi
  done

  return 1
}

if [[ -z "$snapshot_url" ]]; then
  submit_capture || {
    echo "soundsource: could not archive $latest after three attempts" >&2
    exit 1
  }

  # A completed capture can take a moment to become downloadable.
  for ((attempt = 1; attempt <= 10; attempt++)); do
    if prefetch_archive "$snapshot_url"; then
      break
    fi
    if ((attempt < 10)); then
      sleep 6
    fi
  done
fi

if [[ -z "$snapshot_hash" ]]; then
  echo "soundsource: archived capture is not available or failed verification" >&2
  exit 1
fi

source_tmp="$(mktemp ./source.json.XXXXXX)"
jq -n \
  --arg version "$latest" \
  --arg url "$snapshot_url" \
  --arg hash "$snapshot_hash" \
  '{ version: $version, url: $url, hash: $hash }' >"$source_tmp"
mv -- "$source_tmp" source.json
source_tmp=""

echo "soundsource: updated source.json to $latest"
