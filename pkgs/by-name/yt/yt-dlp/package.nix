{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.13-unstable-2026-03-13";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "e68afb28277b4bee39726dbcbb06801edde9f659";
    hash = "sha256-QouGReC3i0BIDUXB3/ZCbrdIi6Y6jb1ICA6aZZcamrA=";
  };
})
