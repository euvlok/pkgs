{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-28";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "5678b282e2a17a8181e682a9681461b9c82ff008";
      hash = "sha256-8ZHnodqUmR2t2yuLfq5Mb7k84DEWppa0P+ifIprV93Y=";
    };
  }
)
