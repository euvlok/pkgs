{
  lib,
  ghidra,
  fetchFromGitHub,
  runCommand,
  symlinkJoin,
  patch,
  python313,
  maven,
  jdk21,
  stripJavaArchivesHook,
  curl,
  coreutils,
  makeWrapper,
  writeShellApplication,
}:
let
  jarVersion = "5.13.1";
  mvnParameters = lib.strings.escapeShellArgs [ "-Pheadless" ];

  upstreamSrc = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = "v${jarVersion}";
    hash = "sha256-fxUY+RKmDkPjCYXz7Fj/TWRBd0IeDap1VZ2NdqbbiJI=";
  };

  src = runCommand "ghidra-mcp-${jarVersion}-patched" { nativeBuildInputs = [ patch ]; } ''
    cp -R "${upstreamSrc}/." "$out"
    chmod -R u+w "$out"
    patch -d "$out" -p1 < "${./bridge-auth-token.patch}"
  '';

  python = python313.withPackages (ps: [
    ps.mcp
    ps.requests
  ]);
  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";

  requiredGhidraJarGroups = [
    {
      root = "Features";
      names = [
        "Base"
        "Decompiler"
        "FunctionID"
        "PDB"
      ];
    }
    {
      root = "Framework";
      names = [
        "DB"
        "Docking"
        "Emulation"
        "FileSystem"
        "Generic"
        "Graph"
        "Gui"
        "Help"
        "Project"
        "SoftwareModeling"
        "Utility"
      ];
    }
    {
      root = "Debug";
      names = [
        "Debugger-api"
        "Debugger-rmi-trace"
        "Framework-TraceModeling"
      ];
    }
  ];

  requiredGhidraJarPaths = lib.lists.concatMap (
    { root, names }:
    map (name: "${root}/${name}/lib/${name}.jar") names
  ) requiredGhidraJarGroups;

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

  bridgeFlags = lib.strings.concatStringsSep " " [
    "${src}/bridge_mcp_ghidra.py"
    "--transport \"$GHIDRA_MCP_BRIDGE_TRANSPORT\""
    "--mcp-host \"$GHIDRA_MCP_BRIDGE_HOST\""
    "--mcp-port \"$GHIDRA_MCP_BRIDGE_PORT\""
    "--no-lazy"
  ];

  installGhidraMavenDeps = repo: ''
    mkdir -p "${repo}"
    ${lib.strings.concatMapStringsSep "\n" (path: ''
      mvn install:install-file \
        -Dmaven.repo.local="${repo}" \
        -Dfile="${ghidra}/lib/ghidra/Ghidra/${path}" \
        -DgroupId="ghidra" \
        -DartifactId="${lib.strings.removeSuffix ".jar" (baseNameOf path)}" \
        -Dversion="${ghidra.version}" \
        -Dpackaging="jar" \
        -DgeneratePom="true"
    '') requiredGhidraJarPaths}
  '';

  normalizeGhidraMavenMetadata = repo: ''
    find "${repo}/ghidra" -name maven-metadata-local.xml -exec \
      sed -i 's#<lastUpdated>.*</lastUpdated>#<lastUpdated>19700101000000</lastUpdated>#' {} +
  '';

  server = maven.buildMavenPackage (finalAttrs: {
    pname = "ghidra-mcp-headless-server";
    version = jarVersion;

    inherit src;

    mvnJdk = jdk21;
    doCheck = false;
    buildOffline = true;
    strictDeps = true;
    mvnHash = "sha256-Vaj51PmXnRtIUnoPjxav0kM9TX5huE5AAJIxmcP+4UY=";
    inherit mvnParameters;
    mvnDepsParameters = mvnParameters;

    nativeBuildInputs = [
      stripJavaArchivesHook
    ];

    postPatch = ''
      substituteInPlace pom.xml \
        --replace-fail "<ghidra.version>12.1</ghidra.version>" \
                       "<ghidra.version>${ghidra.version}</ghidra.version>"
    '';

    mvnFetchExtraArgs = {
      preBuild = installGhidraMavenDeps "$out/.m2";
      postInstall = normalizeGhidraMavenMetadata "$out/.m2";
    };

    afterDepsSetup = installGhidraMavenDeps "$mvnDeps/.m2";

    installPhase = ''
      runHook preInstall

      install -Dm644 "target/GhidraMCP-${finalAttrs.version}.jar" \
        "$out/share/java/GhidraMCP-${finalAttrs.version}.jar"

      runHook postInstall
    '';
  });

  httpd = runCommand "ghidra-mcp-httpd" { nativeBuildInputs = [ makeWrapper ]; } ''
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
      --run '${coreutils}/bin/mkdir -p "$GHIDRA_MCP_STATE/home" "$GHIDRA_MCP_STATE/tmp"' \
      --run 'export HOME="$GHIDRA_MCP_STATE/home"' \
      --add-flags "$flags"
  '';

  bridge = runCommand "ghidra-mcp-bridge" { nativeBuildInputs = [ makeWrapper ]; } ''
    mkdir -p "$out/bin"
    makeWrapper "${lib.meta.getExe' python "python"}" "$out/bin/ghidra-mcp-bridge" \
      --set-default GHIDRA_MCP_BIND_ADDRESS "127.0.0.1" \
      --set-default GHIDRA_MCP_PORT "8089" \
      --set-default GHIDRA_DEBUGGER_URL "http://127.0.0.1:8099" \
      --run 'export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"' \
      --run 'export GHIDRA_MCP_BIND="''${GHIDRA_MCP_BIND:-$GHIDRA_MCP_BIND_ADDRESS}"' \
      --set-default GHIDRA_MCP_BRIDGE_HOST "127.0.0.1" \
      --set-default GHIDRA_MCP_BRIDGE_PORT "8090" \
      --set-default GHIDRA_MCP_BRIDGE_TRANSPORT "stdio" \
      --run 'export GHIDRA_MCP_URL="''${GHIDRA_MCP_URL:-http://$GHIDRA_MCP_BIND:$GHIDRA_MCP_PORT}"' \
      --run 'case " $* " in *" --help "*|*" -h "*) GHIDRA_MCP_SKIP_WAIT=1 ;; esac' \
      --run 'if [ "''${GHIDRA_MCP_SKIP_WAIT:-0}" != 1 ]; then ${lib.meta.getExe' curl "curl"} -fsS --retry 1800 --retry-delay 1 --retry-connrefused "$GHIDRA_MCP_URL/check_connection" >/dev/null; fi' \
      --add-flags ${lib.strings.escapeShellArg bridgeFlags}
  '';

  launcher = writeShellApplication {
    name = "ghidra-mcp-headless";
    runtimeInputs = [
      coreutils
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
    description = "Pinned upstream bethington Ghidra MCP headless backend and bridge launcher";
    homepage = "https://github.com/bethington/ghidra-mcp";
    changelog = "https://github.com/bethington/ghidra-mcp/releases/tag/v${jarVersion}";
    license = lib.licenses.asl20;
    mainProgram = "ghidra-mcp-headless";
    inherit (ghidra.meta) platforms;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
  };
in
symlinkJoin {
  name = "ghidra-mcp-headless-${jarVersion}";

  paths = [
    bridge
    httpd
    launcher
  ];

  passthru = {
    inherit
      bridge
      ghidra
      httpd
      launcher
      server
      src
      upstreamSrc
      ;
  };

  inherit meta;
}
