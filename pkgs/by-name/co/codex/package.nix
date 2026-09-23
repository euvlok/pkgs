{
  codex,
  fetchFromGitHub,
  lib,
  rustPlatform,
}:
let
  sources = lib.importJSON ./source.json;
  upstreamSrc = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = sources.rev;
    hash = sources.srcHash;
  };
in
codex.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version sources.version) {
    version = sources.version;
    src = upstreamSrc;
    sourceRoot = "${upstreamSrc.name}/codex-rs";
    postPatch = ''
      substituteInPlace Cargo.toml \
        --replace-fail 'lto = "thin"' ""
      sed -i '/^codegen-units = /d' Cargo.toml
      sed -i '1i#![recursion_limit = "256"]' chatgpt/src/lib.rs
    '';
    cargoDeps = rustPlatform.fetchCargoVendor {
      name = "codex-${sources.version}-vendor";
      src = upstreamSrc;
      sourceRoot = "${upstreamSrc.name}/codex-rs";
      hash = sources.cargoHash;
    };
  }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      upstreamVersion = sources.version;
    };
  }
)
