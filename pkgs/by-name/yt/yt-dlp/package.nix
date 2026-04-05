{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-04";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "f14d2f2d548a45fef221aa3821e5a1bf450d5c0b";
    hash = "sha256-s0xFV2k/KPgXhKVx7DqLS13bZOU81q7JHlhoDBa7gzk=";
  };
})
