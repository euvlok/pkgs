{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-20";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "97f03660f55696dc9fce56e7ee43fbe3324a9867";
    hash = "sha256-7tK7a2QU2k5G5yup2fmZeD8tBfWHNotszH+tdddaa58=";
  };
})
