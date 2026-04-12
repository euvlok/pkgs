{
  lib,
  runCommand,
  makeWrapper,
  nushell,
  cacert,
  uutils-findutils,
  ffmpeg-full,
  jq,
  gnused,
  callPackage,
  yt-dlp ? (callPackage ../yt-dlp/package.nix { }),
}:
runCommand "yt-dlp-script"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "yt-dlp download helper script";
      mainProgram = "yt-dlp-script";
      platforms = lib.platforms.unix;
    };
  }
  ''
    mkdir -p $out/bin
    makeWrapper ${lib.getExe nushell} $out/bin/yt-dlp-script \
      --add-flags "${./yt-dlp-script.nu}" \
      --prefix PATH : ${
        lib.makeBinPath [
          cacert
          uutils-findutils
          gnused
          ffmpeg-full
          jq
          yt-dlp
        ]
      }
  ''
