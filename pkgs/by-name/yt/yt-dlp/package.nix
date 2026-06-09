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
      rev = "a75d66ae2c3e86e38eb05ae06e4a416077df001b";
      hash = "sha256-o9FApG/uZ0mR8xrb6LyjZt+h2Z8z1a8Q+01QvAVNKIU=";
    };
  }
)
