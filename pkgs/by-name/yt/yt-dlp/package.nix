{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-11";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "cb309b3293c9919cfb55f5d9ffa2c8c109a5f1eb";
      hash = "sha256-Tlph4XDtODU/1Y6/nOD70ucMuC4g6xyfVgANL1b163E=";
    };
  }
)
