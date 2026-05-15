{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-16";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "a85b38621286903b9124fdb05d177983d8273ec7";
      hash = "sha256-CWU759jr5GPZDm4xFhy1y4yC76vvqrNEga78nwY9iSk=";
    };
  }
)
