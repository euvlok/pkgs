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
      rev = "c4f94545c9d3ce356f2f3149c8fde2134073cee2";
      hash = "sha256-yi+ATWTox3VpcTcp0/MxA9WFWIaN/6jYSiES589Ra7E=";
    };
  }
)
