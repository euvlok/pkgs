{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-28";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "1249676e98aecf2131901f10f0230fb5e1bdc17e";
      hash = "sha256-HZewzKsaG4mXzYTcieX2vev8R4dxGUtXQSBXuOhpClY=";
    };
  }
)
