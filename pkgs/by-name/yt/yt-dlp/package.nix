{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-03-28";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "87eaf886f5a1fed00639baf3677ac76281cd98f9";
    hash = "sha256-wD143mYXY/0mXSYawL6ZRC4SGawSX05Z20FrBlLNkXE=";
  };
})
