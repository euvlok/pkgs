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
      rev = "498e51f5da47539f3b4cc52ff85be5f33e7e9d2f";
      hash = "sha256-hk2aHNS4Nnw5ihkLB8bR9mqmLTW7mSy4yNcKxnDHlxo=";
    };
  }
)
