{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  appimageTools,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;
  sources = import ./sources.nix { inherit fetchurl; };

  pname = "helium-browser";
  inherit (sources.${system}) version src;

  meta = {
    description = "Private, fast, and honest web browser based on ungoogled-chromium";
    homepage = "https://github.com/imputnet/helium-macos";
    license = lib.licenses.gpl3Only;
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = with lib.maintainers; [ FlameFlag ];
  };
in
if stdenvNoCC.hostPlatform.isDarwin then
  stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;

    passthru.updateScript = ./update.sh;

    sourceRoot = "Helium.app";

    nativeBuildInputs = [ _7zz ];

    unpackPhase = ''
      7zz x "$src" -snld
    '';

    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -R . "$out/Applications/Helium.app"
      runHook postInstall
    '';
  }
else
  appimageTools.wrapType2 {
    inherit
      pname
      version
      src
      meta
      ;

    passthru.updateScript = ./update.sh;
  }
