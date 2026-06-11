{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-10";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "e47691215f75fe7e9684080d17fadf340c9a8450";
      hash = "sha256-0VBOr7Z+Ccf3d+Fl/HqiaHxSEcrR+hfJ11eETJFzob0=";
    };
  }
)
