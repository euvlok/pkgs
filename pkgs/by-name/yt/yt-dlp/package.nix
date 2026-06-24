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
      rev = "7b03011294c0210802ffc901390006c39152b999";
      hash = "sha256-0DxWJj4q+8/iHkno0t9TBMwYC5AuG++LqkR5StZabCc=";
    };
  }
)
