{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-21";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "646bb31f39614e6c2f7ba687c53e7496394cbadb";
    hash = "sha256-Vk/h5lEDSjNlbwXD6zRXuVjFxSi0u8MJHRThb1j1XDA=";
  };
})
