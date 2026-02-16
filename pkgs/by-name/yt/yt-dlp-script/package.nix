{
  writeShellApplication,
  cacert,
  uutils-findutils,
  ffmpeg-full,
  jq,
  gnused,
  callPackage,
  yt-dlp ? (callPackage ../yt-dlp/package.nix { }),
}:
writeShellApplication {
  name = "yt-dlp-script";
  text = builtins.readFile ./yt-dlp-script.sh;
  runtimeInputs = [
    cacert
    uutils-findutils
    gnused
    ffmpeg-full
    jq
    yt-dlp
  ];
}
