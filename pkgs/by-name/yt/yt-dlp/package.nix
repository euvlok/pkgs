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
      rev = "e8de28e23c1ecb4a12b2c3dec188c07e998c412c";
      hash = "sha256-Ijaz179p8MfVy19o53pCTSGrLtx+4WmLaRJcTMQCUik=";
    };
  }
)
