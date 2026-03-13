{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.13-unstable-2026-03-13";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "990fdf36dd985403cb171e4b92d1d7f01a4e273d";
    hash = "sha256-Sx5otasIqQW8n37cVqGI9j6biwMcEMIboLcyC1dkexk=";
  };
})
