{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-07-01";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "16bdcc525e6a550781d65d6fed92a37800ad95e1";
      hash = "sha256-Z3V/p/DDdI0qVOwU0FAmOCphibxjAWuVpceR+xwuqkI=";
    };
  }
)
