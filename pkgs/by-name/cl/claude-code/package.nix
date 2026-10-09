{
  claude-code,
  lib,
}:
let
  manifest = lib.importJSON ./source.json;
  upstreamVersion = manifest.version;
  baseClaudeCode =
    if lib.versionOlder claude-code.version upstreamVersion then
      claude-code.override { inherit manifest; }
    else
      claude-code;
in
baseClaudeCode.overrideAttrs (prevAttrs: {
  passthru = (prevAttrs.passthru or { }) // {
    updateScript = ./update.sh;
    inherit upstreamVersion;
  };
})
