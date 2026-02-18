{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-17";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "d108ca10b926410ed99031fec86894bfdea8f8eb";
    hash = "sha256-+ZDkMNkYwT8UbqZjjK0jHHE9iuAAPa0e9d/YtP4GMW0=";
  };
})
