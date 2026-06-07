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
      rev = "5faffa999fd33b373d47773e8ee639d072accec2";
      hash = "sha256-dELwDC7bgdsZGbMC5LG6YBklb/u91YekRd/uZ/s4Njg=";
    };
  }
)
