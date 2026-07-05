{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.07.04-unstable-2026-07-04";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "fdec00e0bf530dc6c3cc7b1dd780e95d9ae460e9";
      hash = "sha256-+oHcVylLXFJTRR6jXF6IXvgntXJz0tRdtnwTruRPkoc=";
    };
  }
)
