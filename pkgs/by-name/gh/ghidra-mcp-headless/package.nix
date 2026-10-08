{
  lib,
  callPackage,
  ghidra,
  ghidra-mcp-bridge,
  ghidra-mcp-headless-server,
  ghidra-mcp-httpd,
  symlinkJoin,
  curl,
  coreutils,
  writeShellApplication,
}:
let
  common = callPackage ./common.nix { };
  inherit (common)
    src
    packageVersion
    jarVersion
    stateDefault
    ;
  bridge = ghidra-mcp-bridge;
  server = ghidra-mcp-headless-server;
  httpd = ghidra-mcp-httpd;
  inherit (bridge)
    bridgeApp
    bridgePython
    mcp
    mcpSdkVersion
    ;
  inherit (server) mvnParameters;
  javaMeta = server.meta;

  launcher = writeShellApplication {
    name = "ghidra-mcp-headless";
    runtimeInputs = [
      coreutils
      curl
    ];
    text = ''
      set -euo pipefail

      export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"
      mkdir -p "$GHIDRA_MCP_STATE"

      start_httpd="''${GHIDRA_MCP_START_HTTPD:-1}"
      case " $* " in
        *" --help "*|*" -h "*) start_httpd=0 ;;
      esac

      httpd_pid=""
      bridge_pid=""
      cleanup() {
        if [[ -n "$bridge_pid" ]] && kill -0 "$bridge_pid" 2>/dev/null; then
          kill "$bridge_pid" 2>/dev/null || true
          wait "$bridge_pid" 2>/dev/null || true
        fi
        if [[ -n "$httpd_pid" ]] && kill -0 "$httpd_pid" 2>/dev/null; then
          kill "$httpd_pid" 2>/dev/null || true
          wait "$httpd_pid" 2>/dev/null || true
        fi
      }
      trap cleanup EXIT INT TERM

      if [[ "$start_httpd" != "0" ]]; then
        log="''${GHIDRA_MCP_HTTPD_LOG:-$GHIDRA_MCP_STATE/httpd.log}"
        mkdir -p "$(dirname "$log")"
        ${lib.meta.getExe' httpd "ghidra-mcp-httpd"} >> "$log" 2>&1 &
        httpd_pid=$!

        connect_host="''${GHIDRA_MCP_CONNECT_HOST:-127.0.0.1}"
        connect_port="''${GHIDRA_MCP_PORT:-8089}"
        export GHIDRA_MCP_URL="''${GHIDRA_MCP_URL:-http://$connect_host:$connect_port}"

        if [[ "''${GHIDRA_MCP_SKIP_WAIT:-0}" != "1" ]]; then
          startup_timeout="''${GHIDRA_MCP_STARTUP_TIMEOUT:-120}"
          if [[ ! "$startup_timeout" =~ ^[0-9]+$ ]] || (( startup_timeout == 0 )); then
            echo "GHIDRA_MCP_STARTUP_TIMEOUT must be a positive integer" >&2
            exit 2
          fi

          deadline=$((SECONDS + startup_timeout))

          until curl --fail --silent --max-time 1 "$GHIDRA_MCP_URL/check_connection" >/dev/null 2>&1; do
            if ! kill -0 "$httpd_pid" 2>/dev/null; then
              set +e
              wait "$httpd_pid"
              httpd_status=$?
              set -e
              echo "ghidra-mcp-httpd exited with status $httpd_status; see $log" >&2
              if (( httpd_status == 0 )); then
                exit 1
              fi
              exit "$httpd_status"
            fi
            if (( SECONDS >= deadline )); then
              echo "timed out after ''${startup_timeout}s waiting for $GHIDRA_MCP_URL; see $log" >&2
              exit 1
            fi
            sleep 1
          done
        fi
      fi

      ${lib.meta.getExe' bridge "ghidra-mcp-bridge"} "$@" &
      bridge_pid=$!
      set +e
      wait "$bridge_pid"
      status=$?
      set -e
      trap - EXIT INT TERM
      cleanup
      exit "$status"
    '';
  };

  meta = {
    inherit (javaMeta)
      changelog
      homepage
      license
      platforms
      sourceProvenance
      ;
    description = "Pinned upstream bethington Ghidra MCP headless backend and bridge launcher";
    mainProgram = "ghidra-mcp-headless";
  };
in
symlinkJoin {
  name = "ghidra-mcp-headless-${packageVersion}";
  version = packageVersion;

  paths = [
    bridge
    httpd
    launcher
  ];

  passthru = {
    inherit
      bridge
      bridgeApp
      bridgePython
      jarVersion
      packageVersion
      ghidra
      httpd
      launcher
      mcp
      mcpSdkVersion
      mvnParameters
      server
      src
      ;
    upstreamVersion = jarVersion;
    components = {
      inherit
        bridge
        httpd
        launcher
        server
        ;
    };
    mavenDeps = server.fetchedMavenDeps;
    updateScript = ./update.sh;
  };

  inherit meta;
}
