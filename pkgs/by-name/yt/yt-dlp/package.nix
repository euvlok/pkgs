{ yt-dlp, fetchFromGitHub, lib }:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-03";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "35684c1171dd8b99da825cf43a0b2c06b43824b7";
      hash = "sha256-r3wqC1uYjVa90EqzIdihdKUjA92hMjtNL9kVH7zG70o=";
    };
  }
)
