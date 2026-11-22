# Discover package files once, following nixpkgs' by-name layout

# Type: { baseDirectory, lib } -> Overlay
{ baseDirectory, lib, ... }:
let
  inherit (builtins)
    attrNames
    concatLists
    hasAttr
    listToAttrs
    readDir
    ;

  inherit (lib.attrsets) mapAttrs mapAttrsToList;

  # Package files for a single shard, as name-value pairs
  namesForShard =
    shard: type:
    if type != "directory" then
      [ ]
    else
      map (name: {
        inherit name;
        value = baseDirectory + "/${shard}/${name}/package.nix";
      }) (attrNames (readDir (baseDirectory + "/${shard}")));

  packageFiles = listToAttrs (concatLists (mapAttrsToList namesForShard (readDir baseDirectory)));
in
final: prev:
mapAttrs (
  name: file:
  # Resolve dependencies through the final overlay stack, except for a
  # package overriding its own name, which needs the previous derivation
  final.callPackage file (lib.optionalAttrs (hasAttr name prev) { ${name} = prev.${name}; })
) packageFiles
