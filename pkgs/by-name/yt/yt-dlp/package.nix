{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-25";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "acf8ab7a6e3024325f62426e35a17f365c4d5d54";
      hash = "sha256-UstFk+z6CWky7/jnf9vli8dIbrZjjE5U0Dan/hTNF4I=";
    };
  }
)
