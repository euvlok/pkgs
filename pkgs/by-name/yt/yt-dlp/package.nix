{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.06.09-unstable-2026-06-12";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "707537a03946fbc5707e22be429545c670cd8ec2";
      hash = "sha256-PXi5OnZfekmK7LzOhm0UfomE2LZclvjqy+c5sz4xSpI=";
    };
  }
)
