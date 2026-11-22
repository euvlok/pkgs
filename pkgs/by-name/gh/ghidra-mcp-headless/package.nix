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
  jq,
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
  inherit (server) mvnParameters;
  javaMeta = server.meta;

  launcher = writeShellApplication {
    name = "ghidra-mcp-headless";
    runtimeInputs = [
      coreutils
      curl
      jq
    ];
    text = ''
      # Bridge-only mode leaves upstream instance discovery alone
      export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"
      mkdir -p "$GHIDRA_MCP_STATE"

      start_httpd="''${GHIDRA_MCP_START_HTTPD:-1}"
      case " $* " in
        *" --help "*|*" -h "*) start_httpd=0 ;;
      esac

      if [[ "$start_httpd" == "0" ]]; then
        exec ${lib.getExe bridge} "$@"
      fi

      connect_host="''${GHIDRA_MCP_CONNECT_HOST:-127.0.0.1}"
      connect_port="''${GHIDRA_MCP_PORT:-8089}"
      url="''${GHIDRA_MCP_URL:-http://$connect_host:$connect_port}"
      url="''${url%/}"
      if [[ ! "$url" =~ ^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]+$ ]]; then
        echo "Managed Ghidra requires an HTTP loopback URL with an explicit port" >&2
        exit 2
      fi
      startup_timeout="''${GHIDRA_MCP_STARTUP_TIMEOUT:-120}"
      if [[ ! "$startup_timeout" =~ ^[1-9][0-9]*$ ]]; then
        echo "GHIDRA_MCP_STARTUP_TIMEOUT must be a positive integer" >&2
        exit 2
      fi

      httpd_pid=""
      bridge_pid=""
      trap '
        if [[ -n "$bridge_pid" ]]; then
          kill "$bridge_pid" 2>/dev/null || true
          wait "$bridge_pid" 2>/dev/null || true
        fi
        if [[ -n "$httpd_pid" ]]; then
          kill "$httpd_pid" 2>/dev/null || true
          wait "$httpd_pid" 2>/dev/null || true
        fi
      ' EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      log="''${GHIDRA_MCP_HTTPD_LOG:-$GHIDRA_MCP_STATE/httpd.log}"
      mkdir -p "$(dirname "$log")"
      ${lib.getExe httpd} >> "$log" 2>&1 &
      httpd_pid=$!

      auth=()
      if [[ -n "''${GHIDRA_MCP_AUTH_TOKEN:-}" ]]; then
        auth=(--header @-)
      fi
      deadline=$((SECONDS + startup_timeout))
      while true; do
        if ! kill -0 "$httpd_pid" 2>/dev/null; then
          status=0
          wait "$httpd_pid" || status=$?
          httpd_pid=""
          echo "ghidra-mcp-httpd exited with status $status; see $log" >&2
          exit "$((status == 0 ? 1 : status))"
        fi
        # A live Ghidra on the same port does not prove this process bound it
        if curl -q --fail --silent --noproxy '*' --max-time 1 "''${auth[@]}" \
          "$url/mcp/instance_info" <<< "Authorization: Bearer ''${GHIDRA_MCP_AUTH_TOKEN:-}" |
          jq -e --argjson pid "$httpd_pid" '.pid == $pid and .server_kind == "headless"' \
            >/dev/null; then
          break
        fi
        if (( SECONDS >= deadline )); then
          echo "timed out after ''${startup_timeout}s waiting for Ghidra PID $httpd_pid at $url; see $log" >&2
          exit 1
        fi
        sleep 1
      done

      export GHIDRA_MCP_URL="$url" GHIDRA_MCP_PIN_URL=1
      # Bash gives a background command /dev/null unless stdin is redirected
      exec 3<&0
      ${lib.getExe bridge} "$@" <&3 3<&- &
      bridge_pid=$!
      exec 3<&-
      status=0
      wait "$bridge_pid" || status=$?
      bridge_pid=""
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
      jarVersion
      packageVersion
      ghidra
      httpd
      launcher
      mvnParameters
      server
      src
      ;
    inherit (bridge) mcp mcpSdkVersion;
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
    inherit (common) updateScript;
  };

  inherit meta;
}
