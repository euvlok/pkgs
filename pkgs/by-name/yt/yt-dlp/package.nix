{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-21";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "f532a91cef11075eb5a7809255259b32d2bca8ca";
    hash = "sha256-E/82yxGysXsT6Yy7RY+7zmtQc8rI5Ku+JjoSOaw3XuQ=";
  };
})
