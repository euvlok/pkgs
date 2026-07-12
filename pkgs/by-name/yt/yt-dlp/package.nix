{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.07.04-unstable-2026-07-12";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "6a188aed91fb0a1b9d62f20377015b8fd2c69762";
      hash = "sha256-+Q6n0IaFWTqDxPaWrCTXJSTJ36m4dNrwP3tWk5dUyNg=";
    };
  }
)
