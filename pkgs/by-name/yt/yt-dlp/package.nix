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
      rev = "55a58debec7fa5bbaa119dfbc874fb84dd48c76e";
      hash = "sha256-VtOZ1yr9T7Ek+CMDY8RjYQJW/0aR+HlzqjujrNO11as=";
    };
  }
)
