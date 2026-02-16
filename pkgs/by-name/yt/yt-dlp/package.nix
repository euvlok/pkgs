{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.04-unstable-2026-02-12";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "8d6e0b29bf15365638e0ceeb803a274e4db6157d";
    hash = "sha256-HJgid54DZwSdXt6niDfN2Qctt5SpUv1GmstBGvZWUHQ=";
  };
})
