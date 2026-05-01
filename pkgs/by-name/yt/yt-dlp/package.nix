{ yt-dlp, fetchFromGitHub, lib }:
let
  upstreamVersion = "2026.03.17-unstable-2026-04-30";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "ebf0c0f61e3e578db26b45eb24d643f1a64bf17f";
      hash = "sha256-ovFF1QA1hFJvRdSOSFvDQkHmoOz8LNZghix/+6Si2M8=";
    };
  }
)
