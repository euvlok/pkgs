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
      rev = "d9813a3da6959662841dfb34cad0ee6c07a65d1e";
      hash = "sha256-fJVsq9PUjJquprNrBfexbjPgk8yl+GCxMhBHf6365OU=";
    };
  }
)
