{
  opencode,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "1.17.8";
  upstreamSrc = fetchFromGitHub {
    inherit (opencode.src) owner repo;
    tag = "v${upstreamVersion}";
    hash = "sha256-iReCFIJeJIOIs95v0ReVR/X1PnT5dSnR9O0TniyvPR8=";
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
      outputHash = "sha256-ERywlcNEF9EUW3JDGH8987g+GAj76RylUtegqMvStyg=";
    };
  }
)
