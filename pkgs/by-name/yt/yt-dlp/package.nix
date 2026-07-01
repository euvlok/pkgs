{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-07-01";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "249aa5d6e667308fbf95ae5cfb40eba8177a802c";
      hash = "sha256-a8LcYz/s7R3CUGRLQi66PdrwvI09kYLxPmqnEORhn2Y=";
    };
  }
)
