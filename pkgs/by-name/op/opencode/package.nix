{ opencode, fetchFromGitHub }:
let
  newSrc = fetchFromGitHub {
    inherit (opencode.src) owner repo;
    tag = "v1.4.3";
    hash = "sha256-m+Ue7FWiTjKMAn1QefAwOMfOb2Vybk0mJPV9zcbkOmE=";
  };
in
opencode.overrideAttrs (oldAttrs: {
  version = "1.4.11-unstable-2026-04-18";
  src = newSrc;
  node_modules = oldAttrs.node_modules.overrideAttrs {
    inherit (oldAttrs) version;
    src = newSrc;
    outputHash = "sha256-hVXlQcUuvUudIB35Td6ucBYopM/QOSx59tQbCTqoB/0=";
  };
})
