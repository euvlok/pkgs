{ repoRoot, nixFile }:
let
  flake = builtins.getFlake repoRoot;
  upstream = import flake.inputs.nixpkgs {
    config.allowUnfree = true;
  };
  pkgs = upstream.extend (
    import (repoRoot + "/pkgs/top-level/by-name-overlay.nix") {
      baseDirectory = builtins.toPath (repoRoot + "/pkgs/by-name");
      inherit (upstream) lib;
    }
  );
  file = builtins.toPath nixFile;
  name = builtins.baseNameOf (builtins.dirOf nixFile);
  args = builtins.functionArgs (import file);
  # Evaluate local pins even when the installed override defers to Nixpkgs
  pkg = pkgs.callPackage file (
    upstream.lib.optionalAttrs (builtins.hasAttr name upstream && builtins.hasAttr name args) {
      ${name} = upstream.${name};
    }
    // upstream.lib.optionalAttrs (args ? forUpdate) { forUpdate = true; }
  );
  declaredScript = pkg.updateScript or null;
  script = if declaredScript == null then pkgs.nix-update-script { } else declaredScript;
  spec =
    if builtins.isAttrs script && !pkgs.lib.isDerivation script then script else { command = script; };
  command = map toString (pkgs.lib.toList spec.command);
in
{
  inherit pkgs pkg;
  ${name} = pkg;
  canUpdate =
    (pkg.type or "") == "derivation"
    && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform pkg
    && (declaredScript != null || (pkg ? src && pkg.src ? drvPath));
  updater = pkgs.writeShellScript "package-update" ''
    exec ${pkgs.lib.escapeShellArgs command} "$@"
  '';
  update = {
    inherit command;
    attrPath = spec.attrPath or name;
    inherit (pkg) name;
    pname = pkg.pname or name;
    version = pkg.version or "";
    homepage = pkg.meta.homepage or "";
  };
}
