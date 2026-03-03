{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.21-unstable-2026-03-02";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "bf4dfffe0164385c29a2dcb0367110babe4d4f27";
    hash = "sha256-r2P3JNnnx+HuR0VO9sJcAWqYy3lcfn5bliuDkQNZPWM=";
  };
})
