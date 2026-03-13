{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.03-unstable-2026-03-13";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "92f1d99dbe1e10d942ef0963f625dbc5bc0768aa";
    hash = "sha256-7keuT8k//bcBVVfm6bjEknWBr1sGvdZN63WZ7KyYEg0=";
  };
})
