{
  lib,
  runCommand,
  makeWrapper,
  nushell,
  cacert,
  uutils-findutils,
  ffmpeg,
  jq,
  gnused,
  yt-dlp,
}:
runCommand "yt-dlp-script"
  {
    version = yt-dlp.version;
    nativeBuildInputs = [ makeWrapper ];
    passthru.upstreamVersion = yt-dlp.version;
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
          ffmpeg
          jq
          yt-dlp
        ]
      }
  ''
