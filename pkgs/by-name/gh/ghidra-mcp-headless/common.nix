{ lib, fetchFromGitHub }:
let
  sources = lib.importJSON ./source.json;
  packageVersion = sources.version;
  jarVersion = sources.upstreamVersion;
  upstreamRev = sources.rev;
in
{
  inherit
    sources
    packageVersion
    jarVersion
    upstreamRev
    ;

  src = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = upstreamRev;
    hash = sources.srcHash;
  };

  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";
  reproducibleBuildStamp = "19700101-000000";

  meta = {
    homepage = "https://github.com/bethington/ghidra-mcp";
    changelog = "https://github.com/bethington/ghidra-mcp/blob/${upstreamRev}/CHANGELOG.md";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
