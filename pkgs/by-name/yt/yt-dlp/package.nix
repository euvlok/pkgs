{ yt-dlp, fetchFromGitHub, lib }:
let
  upstreamVersion = "2026.03.17-unstable-2026-04-19";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "165ee77a2be1b3360f1b82e03a933348ecd13e41";
      hash = "sha256-J0dMsfxRM6OBtyqsJyf+hbxUW3m3Soqpv3rqvzij6H8=";
    };
  }
)
