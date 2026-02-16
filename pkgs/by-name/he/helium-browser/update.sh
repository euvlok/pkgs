#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq common-updater-scripts
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [[ -n "${UPDATE_FILE:-}" ]]; then
    WORKING_DIR="$(dirname "${UPDATE_FILE}")"
else
    WORKING_DIR="${SCRIPT_DIR}"
fi

cd "${WORKING_DIR}"

latest_version=$(curl -s https://api.github.com/repos/imputnet/helium-macos/releases/latest | jq -r '.tag_name')

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    printf "Error: Failed to get latest version\n" >&2
    exit 1
fi

printf "Latest version: %s\n" "$latest_version"

current_version=$(grep -A1 'aarch64-darwin' sources.nix | grep 'version' | sed 's/.*"\(.*\)".*/\1/')
if [[ "$current_version" == "$latest_version" ]]; then
    printf "Already at latest version %s\n" "$latest_version"
    exit 0
fi

prefetch_url() {
    local hash
    hash=$(nix-prefetch-url "$1" 2>/dev/null)
    if [[ -z "$hash" ]]; then
        printf "Error: Failed to prefetch %s\n" "$1" >&2
        exit 1
    fi
    printf "sha256:%s" "$hash"
}

darwin_hash=$(prefetch_url "https://github.com/imputnet/helium-macos/releases/download/$latest_version/helium_${latest_version}_arm64-macos.dmg")
linux_arm_hash=$(prefetch_url "https://github.com/imputnet/helium-linux/releases/download/$latest_version/helium-${latest_version}-arm64.AppImage")
linux_x86_hash=$(prefetch_url "https://github.com/imputnet/helium-linux/releases/download/$latest_version/helium-${latest_version}-x86_64.AppImage")

cat > sources.nix << EOF
{ fetchurl }:
{
  aarch64-darwin = {
    version = "$latest_version";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/$latest_version/helium_${latest_version}_arm64-macos.dmg";
      hash = "$darwin_hash";
    };
  };
  aarch64-linux = {
    version = "$latest_version";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/$latest_version/helium-${latest_version}-arm64.AppImage";
      hash = "$linux_arm_hash";
    };
  };
  x86_64-linux = {
    version = "$latest_version";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/$latest_version/helium-${latest_version}-x86_64.AppImage";
      hash = "$linux_x86_hash";
    };
  };
}
EOF

printf "Updated sources.nix to version %s\n" "$latest_version"
