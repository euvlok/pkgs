{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-29";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "500e54cf860e4807d259bfe6a7abb47e51364a3b";
      hash = "sha256-87EZyRUJq53RUHw1X6rRcEdQAbv4VTdsr4jlLTkIX9g=";
    };
  }
)
