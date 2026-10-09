{
  yt-dlp,
  fetchFromGitHub,
  lib,
  nix-update-script,
  forUpdate ? false,
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
  lib.optionalAttrs (forUpdate || lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = sources.rev;
      hash = sources.srcHash;
    };
  }
  // {
    patches = (prevAttrs.patches or [ ]) ++ [ ./prefer-matching-gnome-keyring-application.patch ];
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = nix-update-script {
        extraArgs = [
          "--version=branch=master"
          "--override-filename"
          (toString ./source.json)
        ];
      };
      inherit upstreamVersion;
    };
  }
)
