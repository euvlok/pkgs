{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-26";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "3c279b33cb6d1133624a468e71560c6a75039586";
      hash = "sha256-yUxpkV7ybEwyiOPWT8eqag1pWq8TQT3pGdYknMaab/w=";
    };
  }
)
