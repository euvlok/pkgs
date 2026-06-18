{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-18";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "9ae7df9a22b29e2f81825230c9bba7d444190de0";
      hash = "sha256-16En82SXv3D+lsG1pNA1y6ODozuWbme0byuO0jiO4a4=";
    };
  }
)
