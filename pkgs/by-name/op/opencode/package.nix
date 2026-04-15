{ opencode, fetchFromGitHub }:
opencode.overrideAttrs (oldAttrs: {
  version = "1.4.5-unstable-2026-04-15";
  src = fetchFromGitHub {
    inherit (oldAttrs.src) owner repo;
    tag = "v1.4.3";
    hash = "sha256-m+Ue7FWiTjKMAn1QefAwOMfOb2Vybk0mJPV9zcbkOmE=";
  };
})
