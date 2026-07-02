{
  lib,
  runCommand,
  makeWrapper,
  bashNonInteractive,
  cacert,
  coreutils,
  findutils,
  ffmpeg,
  deno,
  jq,
  python3Packages,
  yt-dlp,
}:
let
  runtimePath = lib.makeBinPath [
    coreutils
    findutils
    ffmpeg
    deno
    jq
    yt-dlp
  ];
in
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
    makeWrapper ${lib.getExe bashNonInteractive} $out/bin/yt-dlp-script \
      --add-flags "${./yt-dlp-script.sh}" \
      --set YT_DLP_SCRIPT_NAME "yt-dlp-script" \
      --set YT_DLP_SCRIPT_PATH "${runtimePath}" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PYTHONPATH : "${python3Packages.makePythonPath [ python3Packages.secretstorage ]}" \
      --prefix PATH : "${runtimePath}"
  ''
