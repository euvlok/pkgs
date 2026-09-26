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
  # Keep nixpkgs' patches, build flags, and runtime wrapper. In particular,
  # its daemon auto-start patch avoids requiring a standalone installation.
  lib.optionalAttrs (lib.versionOlder prevAttrs.version sources.version) {
    version = sources.version;
    src = upstreamSrc;
    sourceRoot = "${upstreamSrc.name}/codex-rs";
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
