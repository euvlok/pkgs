{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  versionCheckHook,
  ripgrep,
  procps,
  claude-code ? null,
}:
let
  manifest = lib.importJSON ./manifest.json;
  upstreamVersion = manifest.version;
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${upstreamVersion}";
  source =
    manifest.platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenvNoCC.hostPlatform.system}");
  standaloneBuild = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "claude-code";
    version = upstreamVersion;

    src = fetchurl {
      url = "${baseUrl}/${source.url}";
      hash = source.hash;
    };

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

    passthru.updateScript = ./update.sh;

    meta = {
      description = "Agentic coding tool that lives in your terminal";
      homepage = "https://github.com/anthropics/claude-code";
      license = lib.licenses.unfree;
      mainProgram = "claude";
      platforms = builtins.attrNames manifest.platforms;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  });
in
if claude-code != null && lib.versionAtLeast claude-code.version upstreamVersion then
  claude-code
else
  standaloneBuild
