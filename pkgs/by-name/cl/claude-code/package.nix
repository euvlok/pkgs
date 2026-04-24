{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  versionCheckHook,
  ripgrep,
  procps,
  # Argument is required by eupkgs' by-name overlay because `claude-code`
  # already exists in nixpkgs; we intentionally ignore it and build a
  # standalone derivation so we don't depend on upstream's internal layout.
  claude-code ? null,
}:
let
  version = "2.1.119";
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}";
  sources = {
    aarch64-darwin = {
      url = "${baseUrl}/darwin-arm64/claude";
      hash = "sha256-Mds0RDCdXQ+Lheh4Li3NhvMffkjBoeg9abCSaMe0+aI=";
    };
    x86_64-darwin = {
      url = "${baseUrl}/darwin-x64/claude";
      hash = "sha256-UrO3XP6AxiaYKy/7Omzhx5eCTyV9wnXPCjwywgK2o98=";
    };
    aarch64-linux = {
      url = "${baseUrl}/linux-arm64/claude";
      hash = "sha256-OCqnPqSwf9jWmOMVm1754bhzn651BbqN3Si4pqYoGc4=";
    };
    x86_64-linux = {
      url = "${baseUrl}/linux-x64/claude";
      hash = "sha256-zKQwU/BilJSVWWsRtv0bWc95ECrbE7rL5mmX5vrkHko=";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "claude-code";
  inherit version;

  src = fetchurl source;

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    makeBinaryWrapper
    versionCheckHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/claude"
    wrapProgram "$out/bin/claude" \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${lib.makeBinPath [ procps ripgrep ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  versionCheckProgramArg = "--version";
  versionCheckKeepEnvironment = [ "HOME" ];

  meta = {
    description = "Agentic coding tool that lives in your terminal";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
