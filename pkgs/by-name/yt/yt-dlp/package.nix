{ yt-dlp, fetchFromGitHub, lib }:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-03";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "27973bae5ea3467ac412bea3b79cbeeb7de71e81";
      hash = "sha256-kKloiXl7SvvC6krKoYjkQpDKgrq4Or8FwZ7gYPq+1fI=";
    };
  }
)
