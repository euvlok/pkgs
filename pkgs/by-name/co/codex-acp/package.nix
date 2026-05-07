{
  codex-acp,
  fetchFromGitHub,
  rustPlatform,
}:
let
  version = "0.13.0";
  src = fetchFromGitHub {
    owner = "zed-industries";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-8Mz3xPhGSjaucZ9c0etGOe4JJC8vJhGFOnAhkwXmhyY=";
  };
in
codex-acp.overrideAttrs (_prevAttrs: {
  inherit version src;

  cargoHash = "sha256-kneMay6MGXhHA0q/usKsLFs/YKmdSHmrgSthzhaPgbk=";
  cargoDeps = rustPlatform.fetchCargoVendor {
    pname = "codex-acp-vendor";
    inherit version src;
    hash = "sha256-kneMay6MGXhHA0q/usKsLFs/YKmdSHmrgSthzhaPgbk=";
  };

  # v0.13.0 no longer needs nixpkgs' v0.12.0 node-version.txt vendor fix.
  postPatch = "";
})
