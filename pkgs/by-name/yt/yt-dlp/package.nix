{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.07.04-unstable-2026-07-09";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "59d9ae606a24a80523da35de9fb75b71eb35b501";
      hash = "sha256-ZGk0ufcQqS4lu8d4vgplt8VNOFrdMDR1bqajI3DEKa4=";
    };
  }
)
