{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.03-unstable-2026-03-11";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "3e36cf9cdb12ef566416c5620a1a95b5a0221017";
    hash = "sha256-74XLxhXoHVzOdqSZnVdQ5SNilVhbb8EW6gscf0fBd1o=";
  };
})
