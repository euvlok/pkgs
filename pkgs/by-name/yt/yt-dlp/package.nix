{
  yt-dlp,
  fetchFromGitHub,
  lib,
  stdenvNoCC,
  python3Packages,
  deno,
  jsRuntime ? deno,
  atomicparsleySupport ? true,
  ffmpegSupport ? true,
  javascriptSupport ? true,
  rtmpSupport ? true,
  withAlias ? false,
  withSecretStorage ? !stdenvNoCC.hostPlatform.isDarwin,
  ...
}:
let
  sources = lib.importJSON ./source.json;
  upstreamVersion = sources.version;
  baseYtDlp = yt-dlp.override {
    inherit
      atomicparsleySupport
      ffmpegSupport
      javascriptSupport
      jsRuntime
      python3Packages
      rtmpSupport
      withAlias
      withSecretStorage
      ;
  };
in
baseYtDlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = sources.rev;
      hash = sources.srcHash;
    };
  }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      inherit upstreamVersion;
    };
  }
)
