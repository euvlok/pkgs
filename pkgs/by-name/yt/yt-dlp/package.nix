{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-27";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "6a24c96f7f61e5e651466cc3d4c6a30982318efe";
      hash = "sha256-lnRWZA+2tB5OJthmhB+y5h3MyaniG6QxJeZbDzTgdBU=";
    };
  }
)
