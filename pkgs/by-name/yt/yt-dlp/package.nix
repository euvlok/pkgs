{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-19";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "acfc00a955208ee780b4cb18ae26de7b62444153";
    hash = "sha256-L1jbdOdG0GumUrZ0Vu8kAHJSQzqj2YeC7ffQElDJXTY=";
  };
})
