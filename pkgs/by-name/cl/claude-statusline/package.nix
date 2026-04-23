{ rustPlatform, lib }:

rustPlatform.buildRustPackage {
  pname = "claude-statusline";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # dashmap 6.1.0 (transitive via jj-lib) ships a rust-toolchain.toml
  # pinning channel = "1.65". Outside the Nix sandbox, rustup honors it
  # and downgrades rustc just for that crate, breaking stable --check-cfg.
  # Strip every vendored rust-toolchain.toml defensively.
  preBuild = ''
    find . -name rust-toolchain.toml -delete 2>/dev/null || true
  '';

  doCheck = false;

  meta = {
    description = "Fast Claude Code / Codex statusline using gix + jj-lib";
    mainProgram = "claude-statusline";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
