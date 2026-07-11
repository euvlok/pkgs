{
  lib,
  stdenv,
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
  mavenHashes = sources.mavenHashes or { };
  supportedSystems = builtins.attrNames mavenHashes;
  mvnHash =
    mavenHashes.${stdenv.hostPlatform.system}
      or (throw "missing ghidra-mcp-headless mvnHash for ${stdenv.hostPlatform.system}");
  mvnParameters = lib.strings.escapeShellArgs [ "-Pheadless" ];
  mvnDepsGhidraVersion = "0";

  src = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = upstreamRev;
    hash = sources.srcHash;
  };

  mcpSdkVersion = "1.28.1";
  mcp = python313Packages.mcp.overridePythonAttrs (old: {
    version = mcpSdkVersion;
    src = fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "python-sdk";
      tag = "v${mcpSdkVersion}";
      hash = "sha256-8nifuun7ShtniimsFr9gYPpjwZEM/5E51GDmZRxQGEc=";
    };
    dependencies = (old.dependencies or [ ]) ++ [
      python313Packages.typing-extensions
      python313Packages.typing-inspection
    ];
    doCheck = false;
  });
  bridgePython = python313.withPackages (_: [ mcp ]);

  bridgeApp = python313Packages.buildPythonApplication {
    pname = "ghidra-mcp-bridge";
    version = packageVersion;
    pyproject = true;

    inherit src;

    build-system = [
      python313Packages.hatchling
    ];

    dependencies = [
      mcp
    ];

    pythonImportsCheck = [ "bridge_mcp_ghidra" ];

    # Upstream's checks use uv dependency groups and cover the bridge plus
    # optional debugger/fun-doc/test subsystems. This derivation intentionally
    # ships only the bridge runtime declared by [project.dependencies].
    doCheck = false;

    meta = commonMeta // {
      description = "Ghidra MCP Python bridge";
      mainProgram = "bridge-mcp-ghidra";
    };
  };
  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";
  reproducibleBuildStamp = "19700101-000000";

  commonMeta = {
    homepage = "https://github.com/bethington/ghidra-mcp";
    changelog = sources.changelog or "https://github.com/bethington/ghidra-mcp/commits/${upstreamRev}";
    license = lib.licenses.asl20;
    platforms = lib.lists.intersectLists ghidra.meta.platforms supportedSystems;
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
    "-m bridge_mcp_ghidra"
    "--transport \"$GHIDRA_MCP_BRIDGE_TRANSPORT\""
    "--mcp-host \"$GHIDRA_MCP_BRIDGE_HOST\""
    "--mcp-port \"$GHIDRA_MCP_BRIDGE_PORT\""
    "--no-lazy"
  ];

  # Upstream resolves Ghidra artifacts through Maven, but nixpkgs packages
  # Ghidra as an application tree. Install the required jars into the local
  # Maven repository used by both dependency fetching and the offline build.
  installGhidraMavenDeps =
    {
      repo,
      version,
      jar,
    }:
    ''
      mkdir -p "${repo}"
      ${lib.strings.concatMapStringsSep "\n" (path: ''
        mvn org.apache.maven.plugins:maven-install-plugin:3.1.2:install-file \
          -Dmaven.repo.local="${repo}" \
          -Dfile="${jar path}" \
          -DgroupId="ghidra" \
          -DartifactId="${lib.strings.removeSuffix ".jar" (baseNameOf path)}" \
          -Dversion="${version}" \
          -Dpackaging="jar" \
          -DgeneratePom="true"
      '') requiredGhidraJarPaths}
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

  normalizeGhidraMavenMetadata = repo: ''
    find "${repo}/ghidra" -name maven-metadata-local.xml -exec \
      sed -i 's#<lastUpdated>.*</lastUpdated>#<lastUpdated>19700101000000</lastUpdated>#' {} +
  '';

  server = maven.buildMavenPackage (finalAttrs: {
    pname = "ghidra-mcp-headless-server";
    version = packageVersion;

    inherit src;

    mvnJdk = jdk21;
    doCheck = false;
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
      postInstall = normalizeGhidraMavenMetadata "$out/.m2";
    };

    afterDepsSetup = installGhidraMavenJars "$mvnDeps/.m2";

    installPhase = ''
      runHook preInstall

      install -Dm644 "target/GhidraMCP-${jarVersion}.jar" \
        "$out/share/java/GhidraMCP-${jarVersion}.jar"

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
        meta = commonMeta // {
          description = "Ghidra MCP Python bridge";
          mainProgram = "ghidra-mcp-bridge";
        };
      }
      ''
        mkdir -p "$out/bin"
        makeWrapper "${lib.meta.getExe bridgeApp}" "$out/bin/ghidra-mcp-bridge" \
          --set-default GHIDRA_MCP_BIND_ADDRESS "127.0.0.1" \
          --set-default GHIDRA_MCP_PORT "8089" \
          --set-default GHIDRA_DEBUGGER_URL "http://127.0.0.1:8099" \
          --set PYTHONDONTWRITEBYTECODE "1" \
          --set PYTHONNOUSERSITE "1" \
          --run 'export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"' \
          --run 'export GHIDRA_MCP_BIND="''${GHIDRA_MCP_BIND:-$GHIDRA_MCP_BIND_ADDRESS}"' \
          --run '${coreutils}/bin/mkdir -p "$GHIDRA_MCP_STATE/tmp" "$GHIDRA_MCP_STATE/runtime"' \
          --run '${coreutils}/bin/chmod 700 "$GHIDRA_MCP_STATE/runtime"' \
          --run 'export TMPDIR="''${TMPDIR:-$GHIDRA_MCP_STATE/tmp}"' \
          --run 'export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$GHIDRA_MCP_STATE/runtime}"' \
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
      "${lib.meta.getExe' jdk21 "jar"}" xf "${server}/share/java/GhidraMCP-${jarVersion}.jar" \
        com/xebyte/version.properties
      tr -d '\r' < com/xebyte/version.properties > version.properties.normalized
      grep -qx 'build.timestamp=${reproducibleBuildStamp}' version.properties.normalized
      grep -qx 'build.number=${reproducibleBuildStamp}' version.properties.normalized

      "${lib.meta.getExe' bridgePython "python"}" -c \
        'import importlib.metadata; print(importlib.metadata.version("mcp"))' > mcp-version
      grep -qx '${mcpSdkVersion}' mcp-version

      "${lib.meta.getExe bridgeApp}" --help > bridge-app-help
      grep -q -- '--transport' bridge-app-help

      export GHIDRA_MCP_STATE="$TMPDIR/state"

      GHIDRA_MCP_SKIP_WAIT=1 "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}" --help > bridge-help
      grep -q -- '--transport' bridge-help

      GHIDRA_MCP_START_HTTPD=0 "${lib.meta.getExe launcher}" --help > launcher-help
      grep -q -- '--transport' launcher-help

      grep -q 'GhidraMCP-${jarVersion}.jar' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'com.xebyte.headless.GhidraMCPHeadlessServer' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q -- '-Djava.io.tmpdir=' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'XDG_RUNTIME_DIR=' "${lib.meta.getExe' httpd "ghidra-mcp-httpd"}"
      grep -q 'PYTHONDONTWRITEBYTECODE' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"
      grep -q 'PYTHONNOUSERSITE' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"
      grep -q 'XDG_RUNTIME_DIR=' "${lib.meta.getExe' bridge "ghidra-mcp-bridge"}"

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
