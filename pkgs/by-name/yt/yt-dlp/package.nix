{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-09";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "7f7bdc974dc61d941d1a0d51c4e21a0fdb7b2d06";
      hash = "sha256-ykqTDPzKKIWRGSQmw2esCRKyYqDZKXRYDeba888tkDU=";
    };
  }
)
