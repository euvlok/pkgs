{
  opencode,
  fetchFromGitHub,
  lib,
}:
let
  upstreamVersion = "pr-33649-assets-unstable-2026-06-24";
  upstreamSrc = fetchFromGitHub {
    inherit (opencode.src) owner repo;
    tag = "v${upstreamVersion}";
    hash = "sha256-IpTD4YCgGNtYlZ6EoyY+YLD81rIFR0D2A4W3uhWSSfo=";
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
