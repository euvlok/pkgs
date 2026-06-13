{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-12";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "9055188250348c3e6e29eee53e5fb3dc2c951977";
      hash = "sha256-2RAhNQlzp2UmpePC4ZN2yknBRtgcZ7paLRzgdcOS8Jc=";
    };
  }
)
