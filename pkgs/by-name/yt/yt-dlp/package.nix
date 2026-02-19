{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-18";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "319a2bda83f5e54054661c56c1391533f82473c2";
    hash = "sha256-S0AMp6RiUKUhoLmGjnbcSBSzNIqKgJnnh5btCfo5UGA=";
  };
})
