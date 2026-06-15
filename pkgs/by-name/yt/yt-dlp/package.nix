{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-15";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "8902f6ba8c7baba8fb43fb08ea1a9ddfef77e998";
      hash = "sha256-fw/hfT+6bKsdT7XETgsLPouD0Ot3mtH3XnnsakxuOX4=";
    };
  }
)
