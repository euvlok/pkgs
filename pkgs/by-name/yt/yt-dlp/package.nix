{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.03-unstable-2026-03-13";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "db62e438a15743b156ca5ebfc6dbe160e9bc1662";
    hash = "sha256-asRBR2X1iJo9x9M4G6LJ2HTwpeMoY3CiWHDW6rnxrx0=";
  };
})
