{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-07-02";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "ad9a6f25f69344ebc060f7be223e5c19fc03e9b5";
      hash = "sha256-l7NqY4Asn/iPx3HCxN5z495WGZuHpBEx0lU55hWCkRI=";
    };
  }
)
