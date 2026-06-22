{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-21";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "d6c411bcd0a0519a0db3b330df2530c8213eb9f0";
      hash = "sha256-2BxGAVe8u7pEajIHQnMhjxAXXgC7Yfv6QxRpEcI9uuM=";
    };
  }
)
