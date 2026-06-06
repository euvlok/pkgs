{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-06-06";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "7fdc46d01619afbb2371b0465d6830602013148f";
      hash = "sha256-jFBH09kUjNygeKU6CXqn2EG1Vetpke3BPQvxFIqv9d8=";
    };
  }
)
