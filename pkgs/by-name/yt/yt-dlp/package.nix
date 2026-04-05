{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-05";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "04b2261cbf1aafb964320062dbb33e74ec613291";
    hash = "sha256-7bdZ2jGqmW2egBh5SJM1O37bgK/aLE4mgGyMzFj8Tpg=";
  };
})
