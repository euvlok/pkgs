{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-03-29";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "2d7b278666bfbf12cf287072498dd275c946b968";
    hash = "sha256-nfwFs9+AL2gfDJVbNl5nO/GoRmc17zzrKwuDbUIjIEs=";
  };
})
