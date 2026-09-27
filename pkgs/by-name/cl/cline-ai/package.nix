{
  fetchurl,
  lib,
  vscode-utils,
}:

let
  source = lib.importJSON ./source.json;
in
vscode-utils.buildVscodeExtension {
  pname = "cline-ai";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  vscodeExtPublisher = "saoudrizwan";
  vscodeExtName = "claude-dev";
  vscodeExtUniqueId = "saoudrizwan.claude-dev";

  passthru = {
    updateScript = ./update.sh;
    upstreamVersion = source.version;
  };

  meta = {
    description = "Autonomous coding agent for VS Code";
    homepage = "https://github.com/cline/cline";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
  };
}
