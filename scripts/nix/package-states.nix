{
  upstreamFlakeRef,
  localFlakeRef,
  system,
  namesJson,
}:
let
  upstreamFlake = builtins.getFlake upstreamFlakeRef;
  localFlake = builtins.getFlake localFlakeRef;
  upstreamPkgs = builtins.getAttr system upstreamFlake.legacyPackages;
  localPkgs = builtins.getAttr system localFlake.legacyPackages;
  names = builtins.fromJSON namesJson;
  stringValue =
    fallback: value:
    let
      result = builtins.tryEval (toString value);
    in
    if result.success then result.value else fallback;
  versionFor =
    pkgs: name:
    if builtins.hasAttr name pkgs then
      stringValue "?" ((builtins.getAttr name pkgs).version or "")
    else
      "";
  stateFor =
    name:
    let
      local = builtins.tryEval (builtins.getAttr name localPkgs);
    in
    {
      effective = if local.success then stringValue "?" (local.value.version or "") else "?";
      pin = if local.success then stringValue "" (local.value.passthru.upstreamVersion or "") else "";
      upstream = versionFor upstreamPkgs name;
    };
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value = stateFor name;
  }) names
)
