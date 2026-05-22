{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-22";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "125bb40468a8618e592d607c1c496095fda764f0";
      hash = "sha256-PHLp7oocI8trOtvkw5V2YFqXohS7+DUIU5qeV9zfWDM=";
    };
  }
)
