{
  lib,
  callPackage,
  ghidra,
  maven,
  jdk21,
  stripJavaArchivesHook,
}:
let
  common = callPackage ../ghidra-mcp-headless/common.nix { };
  inherit (common)
    src
    packageVersion
    jarVersion
    reproducibleBuildStamp
    ;
  inherit (common.sources) mvnHash;
  mvnParameters = lib.escapeShellArgs [ "-Pheadless" ];
  mvnDepsGhidraVersion = "0";

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

  # Upstream resolves Ghidra artifacts through Maven, but nixpkgs packages
  # Ghidra as an application tree. Populate the local Maven layout directly:
  # invoking Maven once per jar adds substantial JVM startup time and only
  # produces these same jar/POM pairs
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

in
maven.buildMavenPackage {
  pname = "ghidra-mcp-headless-server";
  version = packageVersion;

  inherit src;

  mvnJdk = jdk21;
  buildOffline = true;
  doCheck = false;
  strictDeps = true;
  inherit mvnHash;
  inherit mvnParameters;
  # The fetched Maven repository must not embed nixpkgs' Ghidra output: overlay
  # consumers can have different Ghidra store paths and contents. Resolve
  # against deterministic stubs, then install the real jars only in the ordinary
  # (non-fixed-output) build
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
  };

  afterDepsSetup = installGhidraMavenJars "$mvnDeps/.m2";

  installPhase = ''
    runHook preInstall

    install -Dm644 "target/GhidraMCP-${jarVersion}.jar" \
      "$out/share/java/GhidraMCP-${jarVersion}.jar"

    runHook postInstall
  '';

  passthru = {
    upstreamVersion = jarVersion;
    inherit mvnParameters;
    updateScript = ./update.sh;
  };

  meta = common.meta // {
    platforms = lib.intersectLists ghidra.meta.platforms jdk21.meta.platforms;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    description = "Ghidra MCP headless Java server jar";
  };
}
