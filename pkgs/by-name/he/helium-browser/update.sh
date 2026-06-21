#!/usr/bin/env bash
# shellcheck shell=bash
#!nix-shell -i bash -p bash cacert common-updater-scripts coreutils curl jq nix

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [[ -n "${UPDATE_FILE:-}" ]]; then
    WORKING_DIR="$(dirname "${UPDATE_FILE}")"
else
    WORKING_DIR="${SCRIPT_DIR}"
fi

cd "${WORKING_DIR}"

auth_header=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
    auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

latest_version=$(
    curl -fsSL "${auth_header[@]}" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/imputnet/helium-macos/releases/latest \
    | jq -r '.tag_name'
)

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    printf "Error: Failed to get latest version\n" >&2
    exit 1
fi

printf "Latest version: %s\n" "$latest_version"
prefetch_url() {
    local hash
    hash=$(nix-prefetch-url --type sha256 "$1" 2>/dev/null | xargs -I {} nix hash convert --hash-algo sha256 --from nix32 {})
    if [[ -z "$hash" ]]; then
        printf "Error: Failed to prefetch %s\n" "$1" >&2
        exit 1
    fi
    printf "%s" "$hash"
}

darwin_hash=$(prefetch_url "https://github.com/imputnet/helium-macos/releases/download/$latest_version/helium_${latest_version}_arm64-macos.dmg")
linux_arm_hash=$(prefetch_url "https://github.com/imputnet/helium-linux/releases/download/$latest_version/helium-${latest_version}-arm64_linux.tar.xz")
linux_x86_hash=$(prefetch_url "https://github.com/imputnet/helium-linux/releases/download/$latest_version/helium-${latest_version}-x86_64_linux.tar.xz")

jq -n \
    --arg version "$latest_version" \
    --arg darwin_hash "$darwin_hash" \
    --arg linux_arm_hash "$linux_arm_hash" \
    --arg linux_x86_hash "$linux_x86_hash" \
    '{
      platforms: {
        "aarch64-darwin": {
          version: $version,
          url: "https://github.com/imputnet/helium-macos/releases/download/\($version)/helium_\($version)_arm64-macos.dmg",
          hash: $darwin_hash
        },
        "aarch64-linux": {
          version: $version,
          url: "https://github.com/imputnet/helium-linux/releases/download/\($version)/helium-\($version)-arm64_linux.tar.xz",
          hash: $linux_arm_hash
        },
        "x86_64-linux": {
          version: $version,
          url: "https://github.com/imputnet/helium-linux/releases/download/\($version)/helium-\($version)-x86_64_linux.tar.xz",
          hash: $linux_x86_hash
        }
      }
    }' > source.json

printf "Updated source.json to version %s\n" "$latest_version"
