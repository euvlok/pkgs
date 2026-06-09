{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-06-09";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "3d1f8a4a0d4da01fac484bd1593056a1dc9f30a9";
      hash = "sha256-xvxtYxZiNh75AicmZoDE3Cezzr8No9mhBYTbn/xuHXY=";
    };
  }
)
