{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-12";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "a2483524fbf9c1f5406774622d8d048430b320e9";
      hash = "sha256-FwxglhJ/e8pOa0Yl8B9TciE1xd+Y5S5HkgHdVCgbDlE=";
    };
  }
)
