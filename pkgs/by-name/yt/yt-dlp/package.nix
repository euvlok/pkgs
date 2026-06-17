{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-17";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "01f4f06fdd1e1e088981fa4af3422806aefa0c2a";
      hash = "sha256-ilQ5Hm32I4+J94uiP8pDVLzC6E8d4/gOezgHYYLKeZw=";
    };
  }
)
