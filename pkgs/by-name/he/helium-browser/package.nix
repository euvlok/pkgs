{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  makeWrapper,
  autoPatchelfHook ? null,
  addDriverRunpath ? null,
  coreutils ? null,
  xdg-utils ? null,
  makeFontsConf ? null,
  noto-fonts-cjk-sans ? null,
  noto-fonts-cjk-serif ? null,
  adwaita-icon-theme ? null,
  gsettings-desktop-schemas ? null,
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
  ffmpeg ? null,
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
  libICE ? null,
  libSM ? null,
  libXt ? null,
  libXft ? null,
  libxkbcommon ? null,
  libXrandr ? null,
  libXrender ? null,
  libXScrnSaver ? null,
  libxshmfence ? null,
  libXtst ? null,
  libgbm ? null,
  libkrb5 ? null,
  libuuid ? null,
  libva ? null,
  libxml2 ? null,
  nspr ? null,
  nss ? null,
  pango ? null,
  pipewire ? null,
  qt6 ? null,
  snappy ? null,
  udev ? null,
  vulkan-loader ? null,
  wayland ? null,
  zlib ? null,
  glibc ? null,

  # command line arguments which are always set e.g. "--disable-gpu"
  commandLineArgs ? "",
}:

let
  inherit (stdenvNoCC.hostPlatform) system;
  sources = lib.importJSON ./source.json;

  pname = "helium-browser";
  source = sources.platforms.${system} or (throw "helium-browser: unsupported system ${system}");
  inherit (source) version;
  src = fetchurl {
    inherit (source) url hash;
  };

  linuxDeps = [
    glibc
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    ffmpeg
    fontconfig
    freetype
    gcc-unwrapped.lib
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libglvnd
    libICE
    libkrb5
    libSM
    libuuid
    libva
    libX11
    libxcb
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXft
    libXi
    libxkbcommon
    libXrandr
    libXrender
    libXScrnSaver
    libxshmfence
    libXt
    libXtst
    libgbm
    libxml2
    nspr
    nss
    pango
    pipewire
    qt6.qtbase
    qt6.qtwayland
    snappy
    udev
    vulkan-loader
    wayland
    zlib
  ];

  fontsConf = makeFontsConf {
    fontDirectories = [
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
    ];
  };

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

    passthru = {
      updateScript = ./update.sh;
      upstreamVersion = version;
    };

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
        --add-flags ${lib.escapeShellArg commandLineArgs} \
        --add-flags "--extension-mime-request-handling=always-prompt-for-install"
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

    passthru = {
      updateScript = ./update.sh;
      upstreamVersion = version;
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontWrapQtApps = true;

    nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      autoPatchelfHook
      makeWrapper
      qt6.wrapQtAppsHook
    ];
    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux (
      linuxDeps
      ++ [
        adwaita-icon-theme
        gsettings-desktop-schemas
      ]
    );

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/libexec/helium" "$out/bin" "$out/share/applications" "$out/share/icons/hicolor/256x256/apps"
      tar -xJf "$src" -C "$out/libexec/helium" --strip-components=1
      rm -f "$out/libexec/helium/libqt5_shim.so"
      install -Dm644 "$out/libexec/helium/helium.desktop" "$out/share/applications/helium.desktop"
      install -Dm644 "$out/libexec/helium/product_logo_256.png" "$out/share/icons/hicolor/256x256/apps/helium.png"
      substituteInPlace "$out/share/applications/helium.desktop" \
        --replace-fail "Exec=helium %U" "Exec=$out/bin/helium-browser %U" \
        --replace-fail "Exec=helium --incognito" "Exec=$out/bin/helium-browser --incognito"
      sed -i "s|^Exec=helium$|Exec=$out/bin/helium-browser|" "$out/share/applications/helium.desktop"
      ln -s helium.desktop "$out/share/applications/helium-browser.desktop"

      makeWrapper "$out/libexec/helium/helium-wrapper" "$out/bin/helium-browser" \
        --add-flags ${lib.escapeShellArg commandLineArgs} \
        --add-flags "--extension-mime-request-handling=always-prompt-for-install" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}" \
        --set-default CHROME_VERSION_EXTRA nix \
        --set FONTCONFIG_FILE "${fontsConf}" \
        --prefix XDG_DATA_DIRS : "${addDriverRunpath.driverLink}/share:${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${adwaita-icon-theme}/share" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath linuxDeps} \
        --prefix PATH : ${
          lib.makeBinPath [
            coreutils
            xdg-utils
          ]
        } \
        ''${qtWrapperArgs[@]}
      ln -s helium-browser "$out/bin/helium"

      runHook postInstall
    '';
  }
