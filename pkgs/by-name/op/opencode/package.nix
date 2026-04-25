{ opencode, fetchFromGitHub, lib }:
let
  upstreamVersion = "1.14.19-unstable-2026-04-21";
  upstreamSrc = fetchFromGitHub {
    inherit (opencode.src) owner repo;
    tag = "v1.4.3";
    hash = "sha256-m+Ue7FWiTjKMAn1QefAwOMfOb2Vybk0mJPV9zcbkOmE=";
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
      outputHash = "sha256-hVXlQcUuvUudIB35Td6ucBYopM/QOSx59tQbCTqoB/0=";
    };
  }
)
