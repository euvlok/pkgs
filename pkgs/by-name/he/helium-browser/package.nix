{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  makeWrapper,
  autoPatchelfHook ? null,
  alsa-lib ? null,
  at-spi2-atk ? null,
  at-spi2-core ? null,
  atk ? null,
  cairo ? null,
  cups ? null,
  dbus ? null,
  expat ? null,
  fontconfig ? null,
  freetype ? null,
  gcc-unwrapped ? null,
  gdk-pixbuf ? null,
  glib ? null,
  gtk3 ? null,
  gtk4 ? null,
  libdrm ? null,
  libglvnd ? null,
  libX11 ? null,
  libxcb ? null,
  libXcomposite ? null,
  libXcursor ? null,
  libXdamage ? null,
  libXext ? null,
  libXfixes ? null,
  libXi ? null,
  libxkbcommon ? null,
  libXrandr ? null,
  libXrender ? null,
  libXScrnSaver ? null,
  libxshmfence ? null,
  libXtst ? null,
  libgbm ? null,
  nspr ? null,
  nss ? null,
  pango ? null,
  pipewire ? null,
  qt5 ? null,
  qt6 ? null,
  udev ? null,
  vulkan-loader ? null,
  wayland ? null,
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
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      gcc-unwrapped.lib
      gdk-pixbuf
      glib
      gtk3
      gtk4
      libdrm
      libglvnd
      libX11
      libxcb
      libXcomposite
      libXcursor
      libXdamage
      libXext
      libXfixes
      libXi
      libxkbcommon
      libXrandr
      libXrender
      libXScrnSaver
      libxshmfence
      libXtst
      libgbm
      nspr
      nss
      pango
      pipewire
      qt5.qtbase
      qt6.qtbase
      qt6.qtwayland
      udev
      vulkan-loader
      wayland
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
