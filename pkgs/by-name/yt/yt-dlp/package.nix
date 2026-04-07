{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-07";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "8001ff4349fa4eaafd0f88fd8abdf8756090596d";
    hash = "sha256-ui9Jg3nJxsRWaiCwdt50Zfx1hPZbQ0qYeAfTYjOYPAk=";
  };
})
