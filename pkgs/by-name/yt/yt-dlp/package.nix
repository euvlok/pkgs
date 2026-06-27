{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-26";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "d23e6f5a387d5933bc24e1eb5437da8fd563c1f0";
      hash = "sha256-1czmj8QJwvaIeCuLWjsoHLdqJlbGun5IlLHVjTucZBc=";
    };
  }
)
