{
  cacert,
  coreutils,
  gawk,
  git,
  jq,
  nix,
  python3,
  writeShellApplication,
}:

writeShellApplication {
  name = "ghidra-mcp-headless-update";

  runtimeInputs = [
    coreutils
    gawk
    git
    jq
    nix
    python3
  ];

  text = ''
    export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"

    cd "$(dirname "''${UPDATE_FILE:-pkgs/by-name/gh/ghidra-mcp-headless/package.nix}")/../ghidra-mcp-headless"

    repo="bethington/ghidra-mcp"
    tag=$(
      git ls-remote --sort=-version:refname --tags --refs "https://github.com/$repo.git" |
        awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ && !found++ { print substr($2, 11) }'
    )
    if [[ -z "$tag" ]]; then
      echo "no stable tag found for $repo" >&2
      exit 1
    fi
    version="''${tag#v}"
    current_version=$(jq -r .version source.json)
    current_mcp_sdk_version=$(jq -r .mcpSdkVersion source.json)
    nix_system=$(nix eval --impure --raw --expr builtins.currentSystem)
    repo_root=$(realpath ../../../..)

    fetched_source=$(nix store prefetch-file --json --unpack \
      "https://github.com/$repo/archive/refs/tags/$tag.tar.gz")
    src_hash=$(jq -er .hash <<< "$fetched_source")
    src_path=$(jq -er .storePath <<< "$fetched_source")

    mcp_sdk_version=$(python3 - "$src_path" "$version" <<'PY'
    import sys
    import tomllib
    from pathlib import Path

    source = Path(sys.argv[1])
    project = tomllib.loads((source / "pyproject.toml").read_text(encoding="utf-8"))["project"]
    if project["version"] != sys.argv[2]:
        sys.exit(f"tag v{sys.argv[2]} does not match pyproject version {project['version']}")

    lock = tomllib.loads((source / "uv.lock").read_text(encoding="utf-8"))
    versions = {package["version"] for package in lock["package"] if package["name"] == "mcp"}
    if len(versions) != 1:
        sys.exit("uv.lock must pin exactly one MCP Python SDK version")
    print(versions.pop())
    PY
    )

    if [[ ! "$mcp_sdk_version" =~ ^1\.[0-9]+\.[0-9]+$ ]]; then
      echo "upstream locks MCP SDK $mcp_sdk_version, but this package expects SDK 1.x" >&2
      exit 1
    fi

    if [[ "$current_mcp_sdk_version" == "$mcp_sdk_version" ]]; then
      mcp_src_hash=$(jq -r .mcpSrcHash source.json)
    else
      mcp_src_hash=$(
        nix store prefetch-file --json --unpack \
          "https://github.com/modelcontextprotocol/python-sdk/archive/refs/tags/v''${mcp_sdk_version}.tar.gz" |
          jq -r .hash
      )
    fi

    tmp_pkg=$(mktemp -d)
    trap 'rm -rf "$tmp_pkg"; if [[ -n "''${tmp_source:-}" ]]; then rm -f "$tmp_source"; fi' EXIT
    mkdir "$tmp_pkg/gh"
    cp -R ../ghidra-mcp-{headless,headless-server} "$tmp_pkg/gh/"

    jq -n \
      --arg version "$version" \
      --arg srcHash "$src_hash" \
      --arg mcpSdkVersion "$mcp_sdk_version" \
      --arg mcpSrcHash "$mcp_src_hash" \
      --arg mvnHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
      '{
        version: $version,
        srcHash: $srcHash,
        mcpSdkVersion: $mcpSdkVersion,
        mcpSrcHash: $mcpSrcHash,
        mvnHash: $mvnHash
      }' \
      >"$tmp_pkg/gh/ghidra-mcp-headless/source.json"
    nixpkgs_path=$(nix eval --impure --raw "$repo_root#legacyPackages.''${nix_system}.path")
    build_log=$(nix build --impure --no-link --print-build-logs \
      --expr "
        let
          nixpkgs = import $nixpkgs_path { system = \"$nix_system\"; };
          overlay = import $repo_root/pkgs/top-level/by-name-overlay.nix {
            baseDirectory = $tmp_pkg;
            inherit (nixpkgs) lib;
          };
        in (nixpkgs.extend overlay).ghidra-mcp-headless-server.fetchedMavenDeps
      " 2>&1 || true)
    mvn_hash=$(awk '/got: +sha256-/ {print $2; exit}' <<<"$build_log")

    if [[ -z "$mvn_hash" ]]; then
      echo "failed to derive mvnHash; build log:" >&2
      echo "$build_log" >&2
      exit 1
    fi

    tmp_source=$(mktemp ./source.json.XXXXXX)
    jq --arg mvnHash "$mvn_hash" '.mvnHash = $mvnHash' \
      "$tmp_pkg/gh/ghidra-mcp-headless/source.json" >"$tmp_source"
    mv "$tmp_source" source.json

    echo "ghidra-mcp-headless: $current_version -> $version ($tag)"
    echo "mcp Python SDK: $current_mcp_sdk_version -> $mcp_sdk_version"
  '';
}
