{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-16";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "32f1671a906bf375e5b5d39433dd13f917a8dfa7";
      hash = "sha256-FVoPgBrZvpXAJnwUyBIVLQyeWFipD+3kWNJvhkh8eak=";
    };
  }
)
