{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-07";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "9f0fc9a6333b912c83b177542cd3a3cc1c6ff326";
    hash = "sha256-ebwZtsZ71hqKjJVJfbYHe1wke1rpW4xIogyozWxyN5I=";
  };
})
