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
  version = "0.123.0";
  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "rust-v${version}";
    hash = "sha256-v0eqZFObF4Gla8v/MbdchpGZZ0DTL4x2LvX/LNBTzS8=";
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
      runCommand "codex-${version}-${macosWebrtcTriple}" {
        nativeBuildInputs = [ unzip ];
        src = fetchurl {
          url = "https://github.com/livekit/rust-sdks/releases/download/${webrtcTag}/webrtc-${macosWebrtcTriple}.zip";
          hash = macosWebrtcZipHash;
        };
      } ''
        mkdir -p "$out"
        unzip -q "$src" -d "$out"
      ''
    else
      null;
in
codex.overrideAttrs (prevAttrs: {
  inherit version src;

  sourceRoot = "${src.name}/codex-rs";

  cargoDeps = rustPlatform.fetchCargoVendor {
    name = "codex-${version}-vendor";
    inherit src;
    sourceRoot = "${src.name}/codex-rs";
    hash = "sha256-PY0y8yhqdzrgZgKjEWseD5ePTlZM1NWvYNHW76XgOvU=";
  };

  patches = (prevAttrs.patches or [ ]) ++ [
    ./0001-add-external-tui-status-line-command-support.patch
    ./0002-trust-projects-by-default.patch
    ./0003-shift-empty-placeholder-off-cursor-cell.patch
  ];

  env = (prevAttrs.env or { }) // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    LK_CUSTOM_WEBRTC = "${macosWebrtcPrebuilt}/${macosWebrtcTriple}";
  };

  # Patches were authored against the repo root; sourceRoot is codex-rs/.
  patchFlags = [ "-p2" ];
})
