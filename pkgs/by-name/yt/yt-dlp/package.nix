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
      rev = "618b5e446c4379c9d95fe7b30fd6a0fc6af19a70";
      hash = "sha256-iVQKc/tFV4SFJqCRGkD/h0Rk5/vNgcDF9jOYrfdBrz0=";
    };
  }
)
