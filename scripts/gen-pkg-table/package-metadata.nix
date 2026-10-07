{
  localFlakeRef,
  system,
  namesJson,
}:
let
  flake = builtins.getFlake localFlakeRef;
  pkgs = builtins.getAttr system flake.legacyPackages;
  names = builtins.fromJSON namesJson;
  stringValue =
    value:
    let
      result = builtins.tryEval (toString value);
    in
    if result.success then result.value else "";
  metadataFor =
    name:
    let
      result = builtins.tryEval (builtins.getAttr name pkgs);
    in
    if !result.success then
      {
        version = "";
        description = "";
      }
    else
      {
        version = stringValue (result.value.version or "");
        description = stringValue (result.value.meta.description or "");
      };
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value = metadataFor name;
  }) names
)
