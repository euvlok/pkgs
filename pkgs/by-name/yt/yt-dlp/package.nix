{
  yt-dlp,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "2026.03.17-unstable-2026-05-24";
in
yt-dlp.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchFromGitHub {
      inherit (prevAttrs.src) owner repo;
      rev = "98e42eb04486e00bf86479b24dbfe19321f652ee";
      hash = "sha256-iOR/Iv6fWVoPoM9Nx7B9ZSKRW5l9S9VDW/EnYMNXL5g=";
    };
  }
)
