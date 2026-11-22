{
  opencode,
  fetchFromGitHub,
  lib,
  nix-update-script,
  stdenv,
  forUpdate ? false,
}:
let
  # nixpkgs builds different node_modules outputs on Linux and Darwin
  sourceFile = if stdenv.hostPlatform.isDarwin then ./source-darwin.json else ./source.json;
  sources = lib.importJSON sourceFile;
in
opencode.overrideAttrs (
  finalAttrs: prevAttrs:
  # Reuse the upstream 2.x build; older package definitions target a different tree
  lib.optionalAttrs
    (prevAttrs ? node_modules && (forUpdate || lib.versionOlder prevAttrs.version sources.version))
    {
      inherit (sources) version;
      src = fetchFromGitHub {
        inherit (prevAttrs.src) owner repo;
        tag = "v${finalAttrs.version}";
        hash = sources.srcHash;
      };
      node_modules = prevAttrs.node_modules.overrideAttrs {
        outputHash = sources.nodeModulesHash;
      };
    }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      upstreamVersion = sources.version;
      updateScript = nix-update-script {
        extraArgs = [
          "--version-regex=^v([0-9]+\\.[0-9]+\\.[0-9]+)$"
          "--subpackage=node_modules"
          "--override-filename"
          (toString sourceFile)
        ];
      };
    };
  }
)
