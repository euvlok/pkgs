{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-27";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "c13e2f8a20fc1fafb31cba4e6287c874bc0c0cc0";
      hash = "sha256-7Mo9aBMvW2iP7qJUUUXxEOux9tTmiD2wqAFVAb20T7k=";
    };
  }
)
