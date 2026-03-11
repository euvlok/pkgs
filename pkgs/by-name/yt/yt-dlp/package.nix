{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.03-unstable-2026-03-10";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "f2bd3202c0ffa3f0c0069c44ca53b625dca568bc";
    hash = "sha256-55mGScmRFBO81/gX4nczlF8ZHQ+ANTJAZArlN+v3YPw=";
  };
})
