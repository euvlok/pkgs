{ yt-dlp, fetchFromGitHub }:
yt-dlp.overrideAttrs (oldAttrs: {
  version = "2026.02.21-unstable-2026-02-26";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    rev = "6f796a2bff332f72c3f250207cdf10db852f6016";
    hash = "sha256-nFIq+D9SodinrOYfAklhLzff7qNYijAHJM7kGmlKwoE=";
  };
})
