{
  codex,
  fetchFromGitHub,
  lib,
  rustPlatform,
}:
let
  sources = lib.importJSON ./sources.json;
  upstreamSrc = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = sources.rev;
    hash = sources.srcHash;
  };
in
codex.overrideAttrs (
  prevAttrs:
  let
    versionBump = lib.optionalAttrs (lib.versionOlder prevAttrs.version sources.version) {
      version = sources.version;
      src = upstreamSrc;
      sourceRoot = "${upstreamSrc.name}/codex-rs";
      cargoDeps = rustPlatform.fetchCargoVendor {
        name = "codex-${sources.version}-vendor";
        src = upstreamSrc;
        sourceRoot = "${upstreamSrc.name}/codex-rs";
        hash = sources.cargoHash;
      };
    };
  in
  versionBump
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
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
