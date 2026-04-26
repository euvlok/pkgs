{
  codex,
  fetchFromGitHub,
  fetchurl,
  lib,
  runCommand,
  rustPlatform,
  stdenv,
  unzip,
}:
let
  upstreamVersion = "rust-v0.126.0-alpha.3-unstable-2026-04-26";
  upstreamSrc = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "rust-v${upstreamVersion}";
    hash = "sha256-FdtV+CIqTInnegcXrXBxw4aE0JnNDh4GdYKwUDjSk9Y=";
  };
  webrtcTag = "webrtc-24f6822-2";
  macosWebrtcTriple =
    if stdenv.hostPlatform.isAarch64 then
      "mac-arm64-release"
    else if stdenv.hostPlatform.isx86_64 then
      "mac-x64-release"
    else
      throw "Unsupported Darwin architecture for Codex WebRTC prebuilt";
  macosWebrtcZipHash =
    if stdenv.hostPlatform.isAarch64 then
      "sha256-eb5cwV5uBjPEOA4z4XLX6/Gm3Og+ngmXYdYQPw1+tsE="
    else if stdenv.hostPlatform.isx86_64 then
      "sha256-COQh7Wa0KEmM1qUTMMldmP7WncRKPBNJ7RaiRowUyV8="
    else
      null;
  macosWebrtcPrebuilt =
    if stdenv.hostPlatform.isDarwin then
      runCommand "codex-${upstreamVersion}-${macosWebrtcTriple}"
        {
          nativeBuildInputs = [ unzip ];
          src = fetchurl {
            url = "https://github.com/livekit/rust-sdks/releases/download/${webrtcTag}/webrtc-${macosWebrtcTriple}.zip";
            hash = macosWebrtcZipHash;
          };
        }
        ''
          mkdir -p "$out"
          unzip -q "$src" -d "$out"
        ''
    else
      null;
in
codex.overrideAttrs (
  prevAttrs:
  let
    versionBump = lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
      version = upstreamVersion;
      src = upstreamSrc;
      sourceRoot = "${upstreamSrc.name}/codex-rs";
      cargoDeps = rustPlatform.fetchCargoVendor {
        name = "codex-${upstreamVersion}-vendor";
        src = upstreamSrc;
        sourceRoot = "${upstreamSrc.name}/codex-rs";
        hash = "sha256-7rexlmc79eUkwcqTa8rN3GFDy1dWs+0h/SUllZqAcpM=";
      };
    };
  in
  versionBump
  // {
    env =
      (prevAttrs.env or { })
      // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
        LK_CUSTOM_WEBRTC = "${macosWebrtcPrebuilt}/${macosWebrtcTriple}";
      };

    patches = (prevAttrs.patches or [ ]) ++ [
      ./0001-add-external-tui-status-line-command-support.patch
      ./0002-trust-projects-by-default.patch
      ./0003-shift-empty-placeholder-off-cursor-cell.patch
      ./0004-add-richer-status-line-command-telemetry.patch
    ];

    patchFlags = [ "-p2" ];
  }
)
