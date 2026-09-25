{
  codex,
  bubblewrap,
  fetchFromGitHub,
  lib,
  ripgrep,
  rustPlatform,
  stdenv,
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
    postInstall = (prevAttrs.postInstall or "") + ''
      mkdir -p $out/codex-resources $out/codex-path
      cp ${lib.getExe ripgrep} $out/codex-path/rg
      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        cp ${lib.getExe' bubblewrap "bwrap"} $out/codex-resources/bwrap
      ''}
      cat > $out/codex-package.json <<'EOF'
      {
        "layoutVersion": 1,
        "version": "${
          if lib.versionOlder prevAttrs.version sources.version then sources.version else prevAttrs.version
        }",
        "target": "${stdenv.hostPlatform.config}",
        "variant": "codex",
        "entrypoint": "bin/codex",
        "resourcesDir": "codex-resources",
        "pathDir": "codex-path"
      }
      EOF
    '';
    # The daemon copies bin/codex into its managed package. A Nix wrapper
    # would keep executing the original store binary after that copy.
    postFixup = "";
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      upstreamVersion = sources.version;
    };
  }
)
