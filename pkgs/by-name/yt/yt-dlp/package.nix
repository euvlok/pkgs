{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.03-unstable-2026-03-03";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "b8058cdf378cbbf60669b665dea146fb7dc90117";
    hash = "sha256-BPZzMT1IrZvgva/m5tYMaDYoUaP3VmpmcYeOUOwuoUY=";
  };
})
