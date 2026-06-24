{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-24";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "a75ba96fa48522738b91a907773a6fa9efe6e2d4";
      hash = "sha256-SQ3cQjvflwsSGGVeAihFoeB2tGc4vAB7OG0jdc3BPnM=";
    };
  }
)
