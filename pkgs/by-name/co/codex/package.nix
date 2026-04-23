{ codex, fetchFromGitHub, fetchurl, fetchzip, rustPlatform }:
let
  version = "0.92.0-unstable-2026-04-23";
  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "305825abd99fc2ff17d5435b2c67b14459963893";
    hash = "sha256-OwpshFsbPCxY0/+wTya1KXy0N7uIj/tSxAADCnlg8+E=";
  };
  rustyV8Archive = fetchurl {
    url = "https://github.com/denoland/rusty_v8/releases/download/v146.4.0/librusty_v8_release_aarch64-apple-darwin.a.gz";
    hash = "sha256-v+LJvjKlbChUbw+WWCXuaPv2BkBfMQzE4XtEilaM+Yo=";
  };
  webrtcPrebuilt = fetchzip {
    url = "https://github.com/livekit/rust-sdks/releases/download/webrtc-24f6822-2/webrtc-mac-arm64-release.zip";
    hash = "sha256-4IwJM6EzTFgQd2AdX+Hj9NWzmyqXrSioRax2L6GKL1U=";
  };
in
codex.overrideAttrs (oldAttrs: {
  inherit version src;

  sourceRoot = "${src.name}";
  cargoRoot = "codex-rs";
  buildAndTestSubdir = "codex-rs";

  patches = (oldAttrs.patches or [ ]) ++ [
    ./0001-add-external-tui-status-line-command-support.patch
  ];

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "runfiles-0.1.0" = "1sdmgr8gramp4z1kfsmbx083gpinzk8bz3vi0fchbwr1qhnmb6mq";
      "nucleo-0.5.0" = "1hpy62kgzhswhfrhipka9inh4c6iisklmvbsllbbf1njsk314vhy";
      "libwebrtc-0.3.26" = "1nhgk4rdqar6clarzww47kyfxq0abfzwyypsz239palwl70ywwyh";
      "crossterm-0.28.1" = "0vzgpvbri4m4qydkj50ch468az7myy04qh5z2n500p1f4dysv87a";
      "ratatui-0.29.0" = "06jyq7m4ch7d5y2cmsf0pqdyyycqif8qrkgp66qj1ch6rzjx66qw";
      "tokio-tungstenite-0.28.0" = "0p7fi05bf4xmjinfjwd4yy7yc52sl739x6kayi01z323djyj9444";
      "tungstenite-0.27.0" = "0pfk24qw4dzc9xk6pl5qwqk39p4ccld0yrxr8dkj5nwpbnm71ph0";
    };
  };

  env = (oldAttrs.env or { }) // {
    RUSTY_V8_ARCHIVE = "${rustyV8Archive}";
    LK_CUSTOM_WEBRTC = "${webrtcPrebuilt}";
  };
})
