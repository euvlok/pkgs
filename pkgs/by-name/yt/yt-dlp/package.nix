{ yt-dlp, fetchFromGitHub, lib }:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-05";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "c8695f52a91f0d2aabbba7b7200c1099bfa9a3e5";
      hash = "sha256-ThrRgu8p+GRHDoQvUvvrZblDtHFdKnIf6rg3TjVrkoc=";
    };
  }
)
