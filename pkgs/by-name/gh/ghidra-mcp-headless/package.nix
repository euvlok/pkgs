{
  lib,
  ghidra,
  fetchFromGitHub,
  runCommand,
  symlinkJoin,
  python313,
  python313Packages,
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
  packageVersion = sources.version;
  jarVersion = sources.upstreamVersion or packageVersion;
  upstreamRev = sources.rev or "v${jarVersion}";
  supportedSystems = lib.lists.intersectLists ghidra.meta.platforms jdk21.meta.platforms;
  mvnHash = sources.mvnHash;
  mvnParameters = lib.strings.escapeShellArgs [ "-Pheadless" ];
  mvnDepsGhidraVersion = "0";

  src = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = upstreamRev;
    hash = sources.srcHash;
  };

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
    # The nixpkgs expression being overridden may target an older SDK test
    # suite. The bridge checks below exercise this SDK through the consumer
    # that is actually shipped here.
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
    ];

    pythonImportsCheck = [ "bridge_mcp_ghidra" ];

    nativeCheckInputs = [
      python313Packages.pytestCheckHook
      python313Packages.requests
    ];

    # Upstream's default pytest configuration pulls in the repository's
    # optional debugger and fun-doc dependency groups. Run the complete
    # offline bridge/invariant subset against the minimal shipped runtime.
    preCheck = "touch pytest-empty.ini";
    pytestFlags = [
      "-c"
      "pytest-empty.ini"
      "tests/unit/test_bridge_cli.py"
      "tests/unit/test_bridge_utils.py"
      "tests/unit/test_endpoint_catalog.py"
      "tests/unit/test_mcp_tools.py"
      "tests/unit/test_no_default_data_egress.py"
      "tests/unit/test_project_consistency.py"
      "tests/unit/test_response_schemas.py"
      "tests/unit/test_static_tools.py"
      "tests/unit/test_transport_network.py"
    ];

    __darwinAllowLocalNetworking = true;

    meta = bridgeMeta // {
      description = "Ghidra MCP Python bridge";
      mainProgram = "bridge-mcp-ghidra";
    };
  };
  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";
  reproducibleBuildStamp = "19700101-000000";

  commonMeta = {
    homepage = "https://github.com/bethington/ghidra-mcp";
    changelog = "https://github.com/bethington/ghidra-mcp/blob/${upstreamRev}/CHANGELOG.md";
    license = lib.licenses.asl20;
    platforms = supportedSystems;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };

  # The bridge can connect to a Ghidra server on another host and therefore
  # does not inherit the local Ghidra application's narrower platform set.
  bridgeMeta = commonMeta // {
    platforms = python313.meta.platforms;
  };

  javaMeta = commonMeta // {
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

  bridgeFlags = lib.strings.concatStringsSep " " [
    "--transport \"$GHIDRA_MCP_BRIDGE_TRANSPORT\""
    "--mcp-host \"$GHIDRA_MCP_BRIDGE_HOST\""
    "--mcp-port \"$GHIDRA_MCP_BRIDGE_PORT\""
    "--no-lazy"
  ];

  # Upstream resolves Ghidra artifacts through Maven, but nixpkgs packages
  # Ghidra as an application tree. Populate the local Maven layout directly:
  # invoking Maven once per jar adds substantial JVM startup time and only
  # produces these same jar/POM pairs.
  installGhidraMavenDeps =
    {
      repo,
      version,
      jar,
    }:
    ''
      mkdir -p "${repo}"
      ${lib.strings.concatMapStringsSep "\n" (
        path:
        let
          artifactId = lib.strings.removeSuffix ".jar" (baseNameOf path);
          artifactDir = "${repo}/ghidra/${artifactId}/${version}";
        in
        ''
          install -Dm444 "${jar path}" \
            "${artifactDir}/${artifactId}-${version}.jar"
          printf '%s\n' \
            '<?xml version="1.0" encoding="UTF-8"?>' \
            '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
            '  <modelVersion>4.0.0</modelVersion>' \
            '  <groupId>ghidra</groupId>' \
            '  <artifactId>${artifactId}</artifactId>' \
            '  <version>${version}</version>' \
            '  <packaging>jar</packaging>' \
            '</project>' \
            > "${artifactDir}/${artifactId}-${version}.pom"
        ''
      ) requiredGhidraJarPaths}
    '';

  installGhidraMavenStubs = repo: ''
    stub_jar="$TMPDIR/ghidra-maven-stub.jar"
    touch "$stub_jar"
    ${installGhidraMavenDeps {
      inherit repo;
      version = mvnDepsGhidraVersion;
      jar = _: "$stub_jar";
    }}
  '';

  installGhidraMavenJars =
    repo:
    installGhidraMavenDeps {
      inherit repo;
      version = ghidra.version;
      jar = path: "${ghidra}/lib/ghidra/Ghidra/${path}";
    };

  server = maven.buildMavenPackage (finalAttrs: {
    pname = "ghidra-mcp-headless-server";
    version = packageVersion;

    inherit src;

    mvnJdk = jdk21;
    buildOffline = true;
    strictDeps = true;
    inherit mvnHash;
    inherit mvnParameters;
    # The fetched Maven repository must not embed nixpkgs' Ghidra output:
    # overlay consumers can have different Ghidra store paths and contents.
    # Resolve against deterministic stubs, then install the real jars only in
    # the ordinary (non-fixed-output) build.
    mvnDepsParameters = lib.strings.escapeShellArgs [
      "-Pheadless"
      "-Dghidra.version=${mvnDepsGhidraVersion}"
    ];
    # go-offline-maven-plugin does not discover Surefire's dynamically
    # selected JUnit 4 provider.
    manualMvnArtifacts = [
      "org.apache.maven.surefire:surefire-junit4:3.5.6"
    ];

    nativeBuildInputs = [
      stripJavaArchivesHook
    ];

    postPatch = ''
      grep -q '<ghidra.version>[^<][^<]*</ghidra.version>' pom.xml
      sed -i -E \
        's#<ghidra.version>[^<]+</ghidra.version>#<ghidra.version>${ghidra.version}</ghidra.version>#' \
        pom.xml

      sed -i -E \
        -e 's#<build.timestamp>[^<]+</build.timestamp>#<build.timestamp>${reproducibleBuildStamp}</build.timestamp>#' \
        -e 's#<build.number>[^<]+</build.number>#<build.number>${reproducibleBuildStamp}</build.number>#' \
        pom.xml
    '';

    mvnFetchExtraArgs = {
      preBuild = installGhidraMavenStubs "$out/.m2";
    };

    afterDepsSetup = installGhidraMavenJars "$mvnDeps/.m2";

    installPhase = ''
      runHook preInstall

      install -Dm644 "target/GhidraMCP-${jarVersion}.jar" \
        "$out/share/java/GhidraMCP-${jarVersion}.jar"

      runHook postInstall
    '';

    passthru.upstreamVersion = jarVersion;

    meta = javaMeta // {
      description = "Ghidra MCP headless Java server jar";
    };
  });

  httpd =
    runCommand "ghidra-mcp-httpd"
      {
        version = jarVersion;
        nativeBuildInputs = [ makeWrapper ];
        passthru.upstreamVersion = jarVersion;
        meta = javaMeta // {
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
      '';

  bridge =
    runCommand "ghidra-mcp-bridge"
      {
        version = jarVersion;
        nativeBuildInputs = [ makeWrapper ];
        passthru.upstreamVersion = jarVersion;
        meta = bridgeMeta // {
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
      '';

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

  tests = {
    smoke = runCommand "ghidra-mcp-headless-smoke-test" { __darwinAllowLocalNetworking = true; } ''
      set -eu

      test -s "${server}/share/java/GhidraMCP-${jarVersion}.jar"
      "${lib.meta.getExe' jdk21 "jar"}" tf "${server}/share/java/GhidraMCP-${jarVersion}.jar" \
        | grep -q '^com/xebyte/headless/GhidraMCPHeadlessServer.class$'
      "${lib.meta.getExe' jdk21 "jar"}" xf "${server}/share/java/GhidraMCP-${jarVersion}.jar" \
        com/xebyte/version.properties
      tr -d '\r' < com/xebyte/version.properties > version.properties.normalized
      grep -qx 'build.timestamp=${reproducibleBuildStamp}' version.properties.normalized
      grep -qx 'build.number=${reproducibleBuildStamp}' version.properties.normalized

      "${lib.meta.getExe' bridgePython "python3"}" -c \
        'import importlib.metadata; print(importlib.metadata.version("mcp"))' > mcp-version
      grep -qx '${mcpSdkVersion}' mcp-version

      "${lib.meta.getExe bridgeApp}" --help > bridge-app-help
      grep -q -- '--transport' bridge-app-help

      export GHIDRA_MCP_STATE="$TMPDIR/state"

      GHIDRA_MCP_SKIP_WAIT=1 "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}" --help > bridge-help
      grep -q -- '--transport' bridge-help

      GHIDRA_MCP_START_HTTPD=0 "${lib.meta.getExe launcher}" --help > launcher-help
      grep -q -- '--transport' launcher-help

      "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}" --help > httpd-help
      grep -q -- '--bind' httpd-help
      grep -q -- '--file' httpd-help

      grep -q 'GhidraMCP-${jarVersion}.jar' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'com.xebyte.headless.GhidraMCPHeadlessServer' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q -- '-Djava.io.tmpdir=' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'XDG_RUNTIME_DIR=' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'PYTHONDONTWRITEBYTECODE' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"
      grep -q 'PYTHONNOUSERSITE' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"
      grep -q 'XDG_RUNTIME_DIR=' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"
      if grep -q 'GHIDRA_MCP_URL=' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"; then
        echo "standalone bridge must not override upstream transport discovery" >&2
        exit 1
      fi
      if grep -q -- '-m bridge_mcp_ghidra' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"; then
        echo "console-script wrapper must not pass Python -m arguments to argparse" >&2
        exit 1
      fi
      grep -q 'GHIDRA_MCP_STARTUP_TIMEOUT' "${lib.meta.getExe launcher}"
      grep -q '/check_connection' "${lib.meta.getExe launcher}"

      runtime_port="$(
        "${lib.meta.getExe' bridgePython "python3"}" -c \
          'import socket; sock = socket.socket(); sock.bind(("127.0.0.1", 0)); print(sock.getsockname()[1]); sock.close()'
      )"
      runtime_state="$TMPDIR/runtime-test"
      GHIDRA_MCP_STATE="$runtime_state" \
        GHIDRA_MCP_PORT="$runtime_port" \
        GHIDRA_MCP_STARTUP_TIMEOUT=30 \
        "${lib.meta.getExe launcher}" </dev/null \
        > runtime-stdout 2> runtime-stderr
      grep -q "Auto-connected via TCP to http://127.0.0.1:$runtime_port" runtime-stderr
      if "${lib.meta.getExe curl}" --fail --silent --max-time 1 \
        "http://127.0.0.1:$runtime_port/check_connection" >/dev/null 2>&1; then
        echo "combined launcher left ghidra-mcp-httpd running" >&2
        exit 1
      fi
      if GHIDRA_MCP_STATE="$TMPDIR/failed-runtime-test" \
        GHIDRA_MCP_EXTRA_ARGS=--version \
        GHIDRA_MCP_STARTUP_TIMEOUT=5 \
        "${lib.meta.getExe launcher}" </dev/null \
        > failed-runtime-stdout 2> failed-runtime-stderr; then
        echo "combined launcher hid an early ghidra-mcp-httpd exit" >&2
        exit 1
      fi
      grep -q 'ghidra-mcp-httpd exited with status 0' failed-runtime-stderr

      touch "$out"
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
      tests
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
