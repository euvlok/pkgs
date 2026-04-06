{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-05";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "565dcfec4e5c035b5544de4a369f654b8a60e9e6";
    hash = "sha256-aj4nfoQKh/AWR2jZLmIL3zsIWTOwODbGZr9jRN6HmSo=";
  };
})
