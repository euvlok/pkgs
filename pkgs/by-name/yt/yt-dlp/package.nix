{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.07.04-unstable-2026-07-06";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "b3854cc41bc906c905e3b0f7bb39755210acd6d1";
      hash = "sha256-LU6Wp1MIYT/VFpfLeLkW7A/WPVAuAEhx7SEIqrR0okU=";
    };
  }
)
