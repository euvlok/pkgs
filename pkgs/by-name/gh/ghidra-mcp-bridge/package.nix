{
  lib,
  callPackage,
  fetchFromGitHub,
  python313,
  python313Packages,
  runCommand,
  coreutils,
  makeWrapper,
}:
let
  common = callPackage ../ghidra-mcp-headless/common.nix { };
  inherit (common)
    sources
    src
    packageVersion
    jarVersion
    stateDefault
    ;

  mcpSdkVersion = sources.mcpSdkVersion;
  mcp = python313Packages.mcp.overridePythonAttrs (old: {
    version = mcpSdkVersion;
    src = fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "python-sdk";
      tag = "v${mcpSdkVersion}";
      hash = sources.mcpSrcHash;
    };
    dependencies = lib.unique (
      (old.dependencies or [ ])
      ++ [
        python313Packages.typing-extensions
        python313Packages.typing-inspection
      ]
    );
    doCheck = false;
  });
  bridgePython = python313.withPackages (_: [ mcp ]);

  bridgeApp = python313Packages.buildPythonApplication {
    pname = "ghidra-mcp-bridge";
    version = packageVersion;
    pyproject = true;
    strictDeps = true;
    __structuredAttrs = true;

    inherit src;

    build-system = [
      python313Packages.hatchling
    ];

    dependencies = [
      mcp
      python313Packages.pydantic
    ];

    doCheck = false;

    meta = common.meta // {
      platforms = python313.meta.platforms;
      description = "Ghidra MCP Python bridge";
      mainProgram = "bridge-mcp-ghidra";
    };
  };
  bridgeFlags = lib.strings.concatStringsSep " " [
    "--transport \"$GHIDRA_MCP_BRIDGE_TRANSPORT\""
    "--mcp-host \"$GHIDRA_MCP_BRIDGE_HOST\""
    "--mcp-port \"$GHIDRA_MCP_BRIDGE_PORT\""
    "--no-lazy"
  ];

in
runCommand "ghidra-mcp-bridge-${packageVersion}"
  {
    version = packageVersion;
    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      upstreamVersion = jarVersion;
      inherit
        bridgeApp
        bridgePython
        mcp
        mcpSdkVersion
        ;
      updateScript = ./update.sh;
    };
    meta = common.meta // {
      platforms = python313.meta.platforms;
      description = "Ghidra MCP Python bridge";
      mainProgram = "ghidra-mcp-bridge";
    };
  }
  ''
    mkdir -p "$out/bin"
    makeWrapper "${lib.meta.getExe bridgeApp}" "$out/bin/ghidra-mcp-bridge" \
      --set-default GHIDRA_DEBUGGER_URL "http://127.0.0.1:8099" \
      --set PYTHONDONTWRITEBYTECODE "1" \
      --set PYTHONNOUSERSITE "1" \
      --run 'export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"' \
      --run '${coreutils}/bin/mkdir -p "$GHIDRA_MCP_STATE/tmp" "$GHIDRA_MCP_STATE/runtime"' \
      --run '${coreutils}/bin/chmod 700 "$GHIDRA_MCP_STATE/runtime"' \
      --run 'export TMPDIR="''${TMPDIR:-$GHIDRA_MCP_STATE/tmp}"' \
      --run 'export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$GHIDRA_MCP_STATE/runtime}"' \
      --set-default GHIDRA_MCP_BRIDGE_HOST "127.0.0.1" \
      --set-default GHIDRA_MCP_BRIDGE_PORT "8090" \
      --set-default GHIDRA_MCP_BRIDGE_TRANSPORT "stdio" \
      --add-flags ${lib.strings.escapeShellArg bridgeFlags}
  ''
