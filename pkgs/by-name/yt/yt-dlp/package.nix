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
      rev = "2b27a203f7573cb491c8bef77cb4d944cee6f8cf";
      hash = "sha256-pSamWbfUt6gdNDjWGoCgdvwWFYhFKCjxgUAiSUAmbEk=";
    };
  }
)
