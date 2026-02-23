{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.21-unstable-2026-02-22";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "e3118604aa99a5514342d6a002c9b4a3fe1235b4";
    hash = "sha256-/wRhO2hMxte3LptrP08Pyndzvf/mu5YyUo4Vvq8Vabg=";
  };
})
