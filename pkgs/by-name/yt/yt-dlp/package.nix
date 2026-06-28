{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-28";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "f49b551a0c4c25358d2afaeda4ee63989d2d56ab";
      hash = "sha256-Q3jmVmajc6ofe2ZCOyfSFPRFW0mIE4As+bO0Zx4rX0Q=";
    };
  }
)
