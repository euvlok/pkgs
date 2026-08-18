{
  lib,
  runCommand,
  makeWrapper,
  bashNonInteractive,
  cacert,
  coreutils,
  ffmpeg,
  jq,
  python3Packages,
  shellcheck,
  yt-dlp,
}:
let
  runtimePath = lib.makeBinPath [
    coreutils
    ffmpeg
    jq
    yt-dlp
  ];
in
runCommand "yt-dlp-script"
  {
    version = yt-dlp.version;
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    passthru.upstreamVersion = yt-dlp.version;
    meta = {
      description = "yt-dlp download helper script";
      homepage = "https://github.com/euvlok/eupkgs";
      license = lib.licenses.mit;
      mainProgram = "yt-dlp-script";
      platforms = lib.platforms.unix;
    };
  }
  ''
    shellcheck ${./yt-dlp-script.sh} ${./yt-dlp-script-tests.sh}
    YT_DLP_SCRIPT_PATH=${runtimePath} \
      ${lib.getExe bashNonInteractive} ${./yt-dlp-script-tests.sh} ${./yt-dlp-script.sh}

    mkdir -p $out/bin
    makeWrapper ${lib.getExe bashNonInteractive} $out/bin/yt-dlp-script \
      --add-flags "${./yt-dlp-script.sh}" \
      --set YT_DLP_SCRIPT_NAME "yt-dlp-script" \
      --set YT_DLP_SCRIPT_PATH "${runtimePath}" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PYTHONPATH : "${python3Packages.makePythonPath [ python3Packages.secretstorage ]}" \
      --prefix PATH : "${runtimePath}"
  ''
