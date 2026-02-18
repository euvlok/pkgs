{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-18";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "2204cee6d8301e491d8455a2c54fd0e1b23468f5";
    hash = "sha256-RmeCt9o0pgnIGs2+VOy9m3319kFKBi9LvPoUn6OsI/k=";
  };
})
