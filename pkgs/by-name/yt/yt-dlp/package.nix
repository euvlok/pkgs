{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-07-03";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "5aa335ecd9d12251b63b5afb23e166ea63cd7271";
      hash = "sha256-aO5L/PiuCOYyAbCD8tsKOftvvay6yRj3tgzV+ekncTY=";
    };
  }
)
