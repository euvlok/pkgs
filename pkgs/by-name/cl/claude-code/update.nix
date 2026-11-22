{
  cacert,
  coreutils,
  curl,
  jq,
  writeShellApplication,
}:

writeShellApplication {
  name = "claude-code-update";

  runtimeInputs = [
    coreutils
    curl
    jq
  ];

  text = ''
    export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"

    cd "$(dirname "''${UPDATE_FILE:-pkgs/by-name/cl/claude-code/package.nix}")"

    BASE_URL="https://downloads.claude.ai/claude-code-releases"

    VERSION="''${1:-$(curl -fsSL "$BASE_URL/latest")}"

    source_tmp="$(mktemp ./source.json.XXXXXX)"
    trap 'rm -f "$source_tmp"' EXIT
    curl -fsSL "$BASE_URL/$VERSION/manifest.zst.json" --output "$source_tmp"
    jq -e --arg version "$VERSION" '
      .version == $version
      and (.platforms | type == "object" and length > 0)
      and all(.platforms[]; .binary == "claude.zst" or .binary == "claude.exe.zst")
    ' "$source_tmp" >/dev/null
    mv "$source_tmp" source.json
  '';
}
