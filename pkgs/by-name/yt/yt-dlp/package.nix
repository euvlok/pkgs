{ yt-dlp, fetchFromGitHub, lib }:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-05";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "3a12be701c28aff4dd4824adb911cc7987dd86ba";
      hash = "sha256-iAks+xSXkhZCvgwlJEbnPT72Aour5w65Mkjio/4UYxo=";
    };
  }
)
