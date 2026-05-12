{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  makeWrapper,
  autoPatchelfHook ? null,
  gtk3 ? null,
  atk ? null,
  cairo ? null,
  pango ? null,
  atSpi2Atk ? null,
  atSpi2Core ? null,
  nss ? null,
  nspr ? null,
  dbus ? null,
  expat ? null,
  cups ? null,
  alsaLib ? null,
  xorg ? null,
  libxkbcommon ? null,
  libgbm ? null,
  libglvnd ? null,
  udev ? null,
  glibc ? null,

  # command line arguments which are always set e.g. "--disable-gpu"
  commandLineArgs ? "",
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
    mainProgram = "helium-browser";
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

    nativeBuildInputs = [
      _7zz
      makeWrapper
    ];

    unpackPhase = ''
      7zz x "$src" -snld
    '';

    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      cp -R . "$out/Applications/Helium.app"

      makeWrapper "$out/Applications/Helium.app/Contents/MacOS/Helium" "$out/bin/helium-browser" \
        --add-flags ${lib.escapeShellArg commandLineArgs}
      ln -s helium-browser "$out/bin/helium"

      runHook postInstall
    '';
  }
else
  stdenvNoCC.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;

    passthru.updateScript = ./update.sh;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      glibc
      gtk3
      atk
      cairo
      pango
      atSpi2Atk
      atSpi2Core
      nss
      nspr
      dbus
      expat
      cups
      alsaLib
      xorg.libX11
      xorg.libxcb
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      libxkbcommon
      libgbm
      libglvnd
      udev
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/libexec/helium" "$out/bin"
      tar -xJf "$src" -C "$out/libexec/helium" --strip-components=1

      makeWrapper "$out/libexec/helium/helium-wrapper" "$out/bin/helium-browser" \
        --add-flags ${lib.escapeShellArg commandLineArgs}
      ln -s helium-browser "$out/bin/helium"

      runHook postInstall
    '';
  }
