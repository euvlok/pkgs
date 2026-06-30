{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-30";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "e584a65f2a0feee0c6c363b3309e9ebd6065f6b4";
      hash = "sha256-TyNijtU1pnnEAYC58wpvpL/F2wuMgG/I5N+Ao4sXxM8=";
    };
  }
)
