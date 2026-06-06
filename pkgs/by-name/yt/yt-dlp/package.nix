{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-06-06";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "7aac95eae663be82cffeaf2a8c1193a5e349e401";
      hash = "sha256-nZKldU/GWhUvwx+GfwLPMvtuAAJ7/gf93zOgwu7UZXI=";
    };
  }
)
