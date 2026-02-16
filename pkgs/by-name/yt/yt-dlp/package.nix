{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-16";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "abade83f8ddb63a11746b69038ebcd9c1405a00a";
    hash = "sha256-99GENikeIZ0u8TigNMAE8kNOZqazf2eAjnHxq67xnTM=";
  };
})
