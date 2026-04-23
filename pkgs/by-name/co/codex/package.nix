{ codex, fetchFromGitHub, rustPlatform }:
let
  version = "0.123.0";
  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "rust-v${version}";
    hash = "sha256-v0eqZFObF4Gla8v/MbdchpGZZ0DTL4x2LvX/LNBTzS8=";
  };
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
  ];

  # Patches were authored against the repo root; sourceRoot is codex-rs/.
  patchFlags = [ "-p2" ];
})
