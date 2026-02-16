{ baseDirectory, lib, ... }:
let
  inherit (builtins) readDir;

  inherit (lib.attrsets)
    mapAttrs
    mapAttrsToList
    mergeAttrsList
    ;

  # Package files for a single shard
  # Type: String -> String -> AttrsOf Path
  namesForShard =
    shard: type:
    if type != "directory" then
      { }
    else
      mapAttrs (name: _: baseDirectory + "/${shard}/${name}/package.nix") (
        readDir (baseDirectory + "/${shard}")
      );

  # The attribute set mapping names to package files defining them
  packageFiles = mergeAttrsList (mapAttrsToList namesForShard (readDir baseDirectory));
in
self: super:
let
  # For each package, call it with super.callPackage but explicitly pass
  # the original nixpkgs package if it exists (to avoid infinite recursion
  # when a by-name package overrides an existing package)
  callPackageFile =
    name: file:
    super.callPackage file (
      # Explicitly pass the original nixpkgs package if it exists
      # This prevents infinite recursion when the package references itself
      lib.optionalAttrs (super ? ${name}) { ${name} = super.${name}; }
    );
in
mapAttrs callPackageFile packageFiles
