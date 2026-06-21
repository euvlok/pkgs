{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  versionCheckHook,
  autoPatchelfHook ? null,
  alsa-lib ? null,
  glibc ? null,
  bubblewrap ? null,
  socat ? null,
  ripgrep,
  procps,
  writableTmpDirAsHomeHook ? null,
  claude-code ? null,
}:
let
  manifest = lib.importJSON ./source.json;
  upstreamVersion = manifest.version;
  baseUrl = "https://downloads.claude.ai/claude-code-releases";
  platformKey = "${stdenvNoCC.hostPlatform.node.platform}-${stdenvNoCC.hostPlatform.node.arch}";
  platformManifestEntry =
    manifest.platforms.${platformKey}
      or (throw "claude-code: unsupported system ${stdenvNoCC.hostPlatform.system}");
  standaloneBuild = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "claude-code";
    version = upstreamVersion;

    src = fetchurl {
      url = "${baseUrl}/${finalAttrs.version}/${platformKey}/claude";
      sha256 = platformManifestEntry.checksum;
    };

    dontUnpack = true;
    dontBuild = true;
    dontStrip = true;

    nativeBuildInputs = [
      installShellFiles
      makeBinaryWrapper
      versionCheckHook
    ]
    ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
      autoPatchelfHook
      writableTmpDirAsHomeHook
    ];

    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      glibc
      alsa-lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/claude"
      wrapProgram "$out/bin/claude" \
        --set DISABLE_AUTOUPDATER 1 \
        --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
        --set DISABLE_INSTALLATION_CHECKS 1 \
        --set USE_BUILTIN_RIPGREP 0 \
        ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
          --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ alsa-lib ]} \
        ''}\
        --prefix PATH : ${
          lib.makeBinPath (
            [
              procps
              ripgrep
            ]
            ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
              bubblewrap
              socat
            ]
          )
        }
      runHook postInstall
    '';

    doInstallCheck = true;
    versionCheckProgramArg = "--version";
    versionCheckKeepEnvironment = [ "HOME" ];

    passthru = {
      updateScript = ./update.sh;
      upstreamVersion = upstreamVersion;
    };

    meta = {
      description = "Agentic coding tool that lives in your terminal";
      homepage = "https://github.com/anthropics/claude-code";
      license = lib.licenses.unfree;
      mainProgram = "claude";
      platforms = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  });
in
if claude-code != null && lib.versionAtLeast claude-code.version upstreamVersion then
  claude-code
else
  standaloneBuild
