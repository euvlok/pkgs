{
  callPackage,
  lib,
  fetchFromGitHub,
}:
let
  sources = lib.importJSON ./source.json;
  packageVersion = sources.version;
  jarVersion = packageVersion;
  tag = "v${packageVersion}";
in
{
  inherit
    sources
    packageVersion
    jarVersion
    ;

  src = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    inherit tag;
    hash = sources.srcHash;
  };

  updateScript = {
    attrPath = "ghidra-mcp-headless";
    command = lib.getExe (callPackage ./update.nix { });
  };

  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";
  reproducibleBuildStamp = "19700101-000000";

  meta = {
    homepage = "https://github.com/bethington/ghidra-mcp";
    changelog = "https://github.com/bethington/ghidra-mcp/blob/${tag}/CHANGELOG.md";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
