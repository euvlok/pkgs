{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-13";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "b23046bbc8e53f32a3853dc33138f2986f3aed06";
      hash = "sha256-YB/S08CQ7vlj2VUiFbQcy9cyWqrH1SoYFTwDwMbK3BE=";
    };
  }
)
