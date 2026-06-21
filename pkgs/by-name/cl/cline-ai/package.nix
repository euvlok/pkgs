{
  lib,
  fetchFromGitHub,
  runCommand,
  buildNpmPackage,
  biome,
  nodejs_22,
  protobuf,
  vscode-utils,
}:

let
  version = "3.89.2";
  nodejs = nodejs_22;

  src = fetchFromGitHub {
    owner = "cline";
    repo = "cline";
    tag = "v${version}";
    hash = "sha256-m7aJyKHFFvp71PWtbOPGWiiz04znk3Vh7pZjwGa/QPM=";
  };

  rootSrc = runCommand "cline-ai-src-${version}" { } ''
    cp -R ${src}/apps/vscode $out
    chmod -R u+w $out
    cp ${./package-lock.json} $out/package-lock.json
  '';

  webviewSrc = runCommand "cline-ai-webview-src-${version}" { } ''
    cp -R ${src}/apps/vscode/webview-ui $out
    chmod -R u+w $out
    cp ${./webview-package-lock.json} $out/package-lock.json
  '';

  webviewNodeModules = buildNpmPackage {
    pname = "cline-ai-webview-node-modules";
    inherit version nodejs;
    src = webviewSrc;
    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-GN+GqdCFO34t5A/XFlBdxkHb5/XZ83PRQi8guHYo8Xs=";

    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall

      cp -r node_modules $out

      runHook postInstall
    '';
  };

  vsix = buildNpmPackage {
    name = "cline-ai-${version}.vsix";
    pname = "cline-ai-vsix";
    inherit version nodejs;
    src = rootSrc;
    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-vkRDwqMBbn/jG7psOJZj/XKR2UG4oCmIyIJL2nXkojw=";
    npmRebuildFlags = [ "--ignore-scripts" ];

    postPatch = ''
      substituteInPlace package.json \
        --replace-fail '"prepare": "npx husky"' '"prepare": "true"'

      substituteInPlace scripts/build-proto.mjs \
        --replace-fail \
          'const GRPC_TOOLS_PROTOC = path.join(require.resolve("grpc-tools"), "../bin", isWindows ? "protoc.exe" : "protoc")' \
          'const GRPC_TOOLS_PROTOC = "${protobuf}/bin/protoc"'
    '';

    buildPhase = ''
      runHook preBuild

      export BIOME_BINARY=${biome}/bin/biome

      cp -R ${webviewNodeModules} webview-ui/node_modules
      chmod -R u+w webview-ui/node_modules
      npm run package
      npx --offline vsce package --out "$out"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      runHook postInstall
    '';
  };
in
vscode-utils.buildVscodeExtension {
  pname = "cline-ai";
  inherit version;

  src = vsix;

  vscodeExtPublisher = "saoudrizwan";
  vscodeExtName = "claude-dev";
  vscodeExtUniqueId = "saoudrizwan.claude-dev";

  passthru = {
    updateScript = ./update.sh;
    upstreamVersion = version;
  };

  meta = {
    description = "Autonomous coding agent for VS Code";
    homepage = "https://github.com/cline/cline";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
