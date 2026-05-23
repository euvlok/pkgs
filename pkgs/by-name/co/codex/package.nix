{
  codex,
  fetchFromGitHub,
  lib,
  rustPlatform,
  stdenv,
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
      ./0005-refresh-terminal-palette-while-focused.patch
    ];

    patchFlags = [ "-p2" ];

    # Skip tests + install-check for faster local rebuilds.
    doCheck = false;
    doInstallCheck = false;

    postPatch = ''
      # webrtc-sys asks rustc to link libwebrtc statically by default,
      # but nixpkgs provides libwebrtc as a shared library.
      substituteInPlace $cargoDepsCopy/*/webrtc-sys-*/build.rs \
        --replace-fail "cargo:rustc-link-lib=static=webrtc" "cargo:rustc-link-lib=dylib=webrtc"
    ''
    # Keep upstream's release profile (lto=fat, codegen-units=1) on Darwin.
    # Stripping them shrinks build time, but the resulting aarch64-darwin
    # binary grows past ld64's 128MB ARM64 branch range.
    # See NixOS/nixpkgs#515153.
    + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
      substituteInPlace Cargo.toml \
        --replace-fail 'lto = "fat"' "" \
        --replace-fail 'codegen-units = 1' ""
    '';
  }
)
