{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-06-09";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "59bba1be7bb476d4445dc4eae94f602300cb865a";
      hash = "sha256-5T2Jn9jb8U/pcVfU2GGTM8o4611N5Wm29RuOx2Yl50o=";
    };
  }
)
