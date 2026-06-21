{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-20";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "da99b21b2d6e32690d1871afc9e9779701dd7f8c";
      hash = "sha256-SLc8GkhRDILnONTSIPPDcd0wI2wqlm8UTA+VAeal2Oo=";
    };
  }
)
