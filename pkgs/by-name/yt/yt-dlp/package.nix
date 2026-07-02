{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-07-02";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "40dd052c03c2d1b5c180f393d9344be2bd718ba3";
      hash = "sha256-vVbv5xPVadtDIDcqVqHOvm53RqKhd8TBPw+/83H0RGM=";
    };
  }
)
