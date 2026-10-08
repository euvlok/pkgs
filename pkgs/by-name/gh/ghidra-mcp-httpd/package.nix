{
  lib,
  callPackage,
  ghidra,
  ghidra-mcp-headless-server,
  jdk21,
  runCommand,
  coreutils,
  makeWrapper,
}:
let
  common = callPackage ../ghidra-mcp-headless/common.nix { };
  inherit (common) packageVersion jarVersion stateDefault;
  server = ghidra-mcp-headless-server;

  ghidraClasspathRoots = [
    "Debug"
    "Features"
    "Framework"
    "Processors"
  ];

  httpdFlags = lib.strings.concatStringsSep " " [
    "\${JAVA_OPTS:-}"
    "\${GHIDRA_USER:+-Duser.name=\"$GHIDRA_USER\"}"
    "-Duser.home=\"$GHIDRA_MCP_STATE/home\""
    "-Djava.io.tmpdir=\"$GHIDRA_MCP_STATE/tmp\""
    "-Dghidra.home=\"$GHIDRA_HOME\""
    "-Dapplication.name=GhidraMCP"
    "-classpath @classpath@"
    "com.xebyte.headless.GhidraMCPHeadlessServer"
    "--bind \"$GHIDRA_MCP_BIND\""
    "--port \"$GHIDRA_MCP_PORT\""
    "\${PROGRAM_FILE:+--file \"$PROGRAM_FILE\"}"
    "\${PROJECT_PATH:+--project \"$PROJECT_PATH\"}"
    "\${PROGRAM_NAME:+--program \"$PROGRAM_NAME\"}"
    "\${GHIDRA_MCP_EXTRA_ARGS:-}"
  ];

in
runCommand "ghidra-mcp-httpd-${packageVersion}"
  {
    version = packageVersion;
    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      upstreamVersion = jarVersion;
      inherit server;
      updateScript = ./update.sh;
    };
    meta = server.meta // {
      description = "Ghidra MCP headless HTTP daemon";
      mainProgram = "ghidra-mcp-httpd";
    };
  }
  ''
    classpath="${server}/share/java/GhidraMCP-${jarVersion}.jar"
    for root in ${lib.strings.escapeShellArgs ghidraClasspathRoots}; do
      for jar in "${ghidra}/lib/ghidra/Ghidra/$root"/*/lib/*.jar; do
        classpath="$classpath:$jar"
      done
    done

    flags=${lib.strings.escapeShellArg httpdFlags}
    flags="''${flags//@classpath@/$classpath}"

    mkdir -p "$out/bin"
    makeWrapper "${lib.meta.getExe' jdk21 "java"}" "$out/bin/ghidra-mcp-httpd" \
      --set GHIDRA_HOME "${ghidra}/lib/ghidra" \
      --set-default GHIDRA_MCP_BIND_ADDRESS "127.0.0.1" \
      --set-default GHIDRA_MCP_PORT "8089" \
      --set-default GHIDRA_MCP_ALLOW_SCRIPTS "" \
      --set-default GHIDRA_MCP_AUTH_TOKEN "" \
      --set-default GHIDRA_MCP_ARCHIVE_URL "" \
      --set-default GHIDRA_MCP_FILE_ROOT "" \
      --set-default GHIDRA_MCP_PROJECT_FOLDER "" \
      --set-default GHIDRA_USER "" \
      --set JAVA_HOME "${jdk21.home}" \
      --run 'export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"' \
      --run 'export GHIDRA_MCP_BIND="''${GHIDRA_MCP_BIND:-$GHIDRA_MCP_BIND_ADDRESS}"' \
      --run '${coreutils}/bin/mkdir -p "$GHIDRA_MCP_STATE/home" "$GHIDRA_MCP_STATE/tmp" "$GHIDRA_MCP_STATE/runtime"' \
      --run '${coreutils}/bin/chmod 700 "$GHIDRA_MCP_STATE/runtime"' \
      --run 'export TMPDIR="$GHIDRA_MCP_STATE/tmp"' \
      --run 'export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$GHIDRA_MCP_STATE/runtime}"' \
      --run 'export HOME="$GHIDRA_MCP_STATE/home"' \
      --add-flags "$flags"
  ''
