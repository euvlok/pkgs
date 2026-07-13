{
  opencode,
  fetchFromGitHub,
  lib,
}:
let
  sources = lib.importJSON ./source.json;
  upstreamVersion = sources.version;
  upstreamSrc = fetchFromGitHub {
    inherit (opencode.src) owner repo;
    rev = sources.rev;
    hash = sources.srcHash;
  };
in
opencode.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = upstreamSrc;
    node_modules = prevAttrs.node_modules.overrideAttrs {
      version = upstreamVersion;
      src = upstreamSrc;
      outputHash = sources.nodeModulesHash;
    };
  }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      inherit upstreamVersion;
    };
  }
)
