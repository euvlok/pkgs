{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.21-unstable-2026-02-21";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "e2a9cc7d137c88843e064bc9ea11cdca5cd4c82a";
    hash = "sha256-r9I/zLyqGPeIzsHsLxJcfnLC3jpuyKMyX1UaMoM08jk=";
  };
})
