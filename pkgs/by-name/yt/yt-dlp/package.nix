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
      rev = "8bdfbfd4461a643e5c37a232b0efd7bcd86a3091";
      hash = "sha256-HvuX4yGmHhywW6gmC4EIaUZwJzMxiuJUJWeUMgMUGgc=";
    };
  }
)
