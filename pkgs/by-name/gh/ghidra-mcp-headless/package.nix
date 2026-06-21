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
  sources = lib.importJSON ./source.json;
  jarVersion = sources.version;
  mvnParameters = lib.strings.escapeShellArgs [ "-Pheadless" ];

  upstreamSrc = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = "v${jarVersion}";
    hash = sources.srcHash;
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

  commonMeta = {
    homepage = "https://github.com/bethington/ghidra-mcp";
    changelog = "https://github.com/bethington/ghidra-mcp/releases/tag/v${jarVersion}";
    license = lib.licenses.asl20;
    inherit (ghidra.meta) platforms;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
  };

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

  # Upstream resolves Ghidra artifacts through Maven, but nixpkgs packages
  # Ghidra as an application tree. Install the required jars into the local
  # Maven repository used by both dependency fetching and the offline build.
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
    inherit (sources) mvnHash;
    inherit mvnParameters;
    mvnDepsParameters = mvnParameters;

    nativeBuildInputs = [
      stripJavaArchivesHook
    ];

    postPatch = ''
      grep -q '<ghidra.version>[^<][^<]*</ghidra.version>' pom.xml
      sed -i -E \
        's#<ghidra.version>[^<]+</ghidra.version>#<ghidra.version>${ghidra.version}</ghidra.version>#' \
        pom.xml
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

    passthru.upstreamVersion = jarVersion;

    meta = commonMeta // {
      description = "Ghidra MCP headless Java server jar";
    };
  });

  httpd =
    runCommand "ghidra-mcp-httpd"
      {
        version = jarVersion;
        nativeBuildInputs = [ makeWrapper ];
        passthru.upstreamVersion = jarVersion;
        meta = commonMeta // {
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
          --run '${coreutils}/bin/mkdir -p "$GHIDRA_MCP_STATE/home" "$GHIDRA_MCP_STATE/tmp"' \
          --run 'export HOME="$GHIDRA_MCP_STATE/home"' \
          --add-flags "$flags"
      '';

  bridge =
    runCommand "ghidra-mcp-bridge"
      {
        version = jarVersion;
        nativeBuildInputs = [ makeWrapper ];
        passthru.upstreamVersion = jarVersion;
        meta = commonMeta // {
          description = "Ghidra MCP Python bridge";
          mainProgram = "ghidra-mcp-bridge";
        };
      }
      ''
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
          --set-default GHIDRA_MCP_CONNECT_HOST "127.0.0.1" \
          --run 'export GHIDRA_MCP_URL="''${GHIDRA_MCP_URL:-http://$GHIDRA_MCP_CONNECT_HOST:$GHIDRA_MCP_PORT}"' \
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

  tests = {
    smoke = runCommand "ghidra-mcp-headless-smoke-test" { } ''
      set -eu

      test -s "${server}/share/java/GhidraMCP-${jarVersion}.jar"
      "${lib.meta.getExe' jdk21 "jar"}" tf "${server}/share/java/GhidraMCP-${jarVersion}.jar" \
        | grep -q '^com/xebyte/headless/GhidraMCPHeadlessServer.class$'

      export GHIDRA_MCP_STATE="$TMPDIR/state"

      GHIDRA_MCP_SKIP_WAIT=1 "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}" --help > bridge-help
      grep -q -- '--transport' bridge-help

      GHIDRA_MCP_START_HTTPD=0 "${lib.meta.getExe launcher}" --help > launcher-help
      grep -q -- '--transport' launcher-help

      grep -q 'GhidraMCP-${jarVersion}.jar' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'com.xebyte.headless.GhidraMCPHeadlessServer' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"

      touch "$out"
    '';
  };

  meta = {
    inherit (commonMeta)
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
  name = "ghidra-mcp-headless-${jarVersion}";
  version = jarVersion;

  paths = [
    bridge
    httpd
    launcher
  ];

  passthru = {
    inherit
      bridge
      jarVersion
      ghidra
      httpd
      launcher
      mvnParameters
      server
      src
      tests
      upstreamSrc
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
