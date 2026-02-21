{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-21";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "81bdea03f3414dd4d086610c970ec14e15bd3d36";
    hash = "sha256-ArfmE8j8wNAnUnPpVZoktYtUf+p21Sn+5okhdHQlyhs=";
  };
})
