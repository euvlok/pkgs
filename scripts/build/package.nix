{
  lib,
  stdenvNoCC,
  bun,
  cacert,
  git,
  nix,
  writableTmpDirAsHomeHook,
}:
let
  manifests = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [
      ../../package.json
      ../../bun.lock
    ];
  };
  nodeModules = stdenvNoCC.mkDerivation {
    pname = "eupkgs-scripts-node-modules";
    version = "0.0.0";
    src = manifests;
    nativeBuildInputs = [
      bun
      cacert
      writableTmpDirAsHomeHook
    ];
    impureEnvVars = lib.fetchers.proxyImpureEnvVars;
    dontConfigure = true;
    dontFixup = true;
    buildPhase = ''
      runHook preBuild
      bun install --production --frozen-lockfile --ignore-scripts --no-progress
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R node_modules "$out/node_modules"
      runHook postInstall
    '';
    outputHash = "sha256-qhlo32z+mnH+isXANuCJm9ULfMZgd76wjKUvnk2LY1A=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };
in
stdenvNoCC.mkDerivation {
  pname = "eupkgs-scripts";
  version = "0.0.0";
  src = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [
      ../../package.json
      ../../bun.lock
      (lib.fileset.fileFilter (file: file.hasExt "ts" || file.hasExt "nix") ../.)
    ];
  };
  nativeBuildInputs = [ bun ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    cp -R ${nodeModules}/node_modules node_modules
    bun run build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/eupkgs" "$out/bin"
    cp -R dist/. "$out/share/eupkgs/"
    for command in update status gen-pkg-table changed-packages build-packages; do
      cat > "$out/bin/$command" <<SCRIPT
    #!${stdenvNoCC.shell}
    export EUPKGS_REPO_ROOT="\''${EUPKGS_REPO_ROOT:-\$PWD}"
    export PATH="${
      lib.makeBinPath [
        bun
        git
        nix
      ]
    }:\$PATH"
    exec ${lib.getExe bun} "$out/share/eupkgs/$command.js" "\$@"
    SCRIPT
      chmod +x "$out/bin/$command"
    done
    runHook postInstall
  '';
  meta = {
    description = "Bun TypeScript helpers for the eupkgs flake";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
