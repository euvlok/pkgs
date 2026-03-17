{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.13-unstable-2026-03-17";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "7fab4c2b23e16c4a4f94020a37a6bdf8d502be37";
    hash = "sha256-tLFhmERWE8B2vr+l2CrbzFOa+EDAcCWCPDD0ieid5cI=";
  };
})
