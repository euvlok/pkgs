{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-18";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "4af5541bb56b08d462f32773dfa15c207de13b74";
      hash = "sha256-yshN/vnW2JTjx+LQGmsA7xbcYSCrNjbNLKacwRjGCks=";
    };
  }
)
