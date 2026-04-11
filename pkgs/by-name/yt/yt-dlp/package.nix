{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-10";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "2c28ee5d76d2c0d350407fd81dbdd71394b67993";
    hash = "sha256-7XqUI1J3U2radzEsNpPgHnELods6dCoQDfZgYir5doQ=";
  };
})
