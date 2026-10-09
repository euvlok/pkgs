{
  opencode,
  fetchFromGitHub,
  lib,
  nix-update-script,
  forUpdate ? false,
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
  lib.optionalAttrs (forUpdate || lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = upstreamSrc;
  }
  // {
    passthru =
      (prevAttrs.passthru or { })
      // {
        updateScript = nix-update-script {
          extraArgs = [
            "--subpackage=node_modules"
            "--override-filename"
            (toString ./source.json)
          ];
        };
        inherit upstreamVersion;
      }
      // lib.optionalAttrs (forUpdate || lib.versionOlder prevAttrs.version upstreamVersion) {
        node_modules = prevAttrs.passthru.node_modules.overrideAttrs {
          version = upstreamVersion;
          src = upstreamSrc;
          outputHash = sources.nodeModulesHash;
        };
      };
  }
)
