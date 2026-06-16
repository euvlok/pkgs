{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-16";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "ad6b5f4b3552472c17b3955a3f1525296bed6137";
      hash = "sha256-SGQ+ote2ogiv2jGabUWnZoN2TnwuiO4DDaUHRQ8zL58=";
    };
  }
)
