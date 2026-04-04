{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.03.17-unstable-2026-04-04";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "0f45ecc920f31c3c5704c62bad8da2e2844ff9bc";
    hash = "sha256-FLAR2FPeZSR1+omFUgR1JL8y/9LFVc9N9F8YvA1XdQI=";
  };
})
