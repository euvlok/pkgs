{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-07";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "88c8a68eb52268111e224293e9a6519944971096";
    hash = "sha256-NCrgtMvCF+hgZD6WTjafukXD4TciULWsOYowPr467AI=";
  };
})
