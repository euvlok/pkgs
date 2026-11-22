{
  lib,
  callPackage,
  stdenvNoCC,
  fetchurl,
  _7zz,
  makeShellWrapper,
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
  at-spi2-core ? null,
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
  inherit (stdenvNoCC.hostPlatform) isDarwin system;
  inherit (lib.importJSON ./source.json) platforms;

  source = platforms.${system} or (throw "helium-browser: unsupported system ${system}");
  wrapperFlags = lib.escapeShellArgs [
    "--add-flags"
    commandLineArgs
    "--add-flags"
    "--extension-mime-request-handling=always-prompt-for-install"
  ];

  linuxDeps = [
    glibc
    alsa-lib
    at-spi2-core
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

  inherit (addDriverRunpath) driverLink;
  xdgDataDirs = lib.concatStringsSep ":" [
    "${driverLink}/share"
    "${gtk3}/share/gsettings-schemas/${gtk3.name}"
    "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}"
    "${adwaita-icon-theme}/share"
  ];

in
stdenvNoCC.mkDerivation (
  {
    pname = "helium-browser";
    inherit (source) version;
    src = fetchurl {
      inherit (source) url hash;
    };

    dontConfigure = true;
    dontBuild = true;
    nativeBuildInputs = [
      makeShellWrapper
    ]
    ++ (
      if isDarwin then
        [ _7zz ]
      else
        [
          autoPatchelfHook
          qt6.wrapQtAppsHook
        ]
    );

    passthru = {
      updateScript = lib.getExe (callPackage ./update.nix { });
      upstreamVersion = source.version;
    };

    meta = {
      description = "Private, fast, and honest web browser based on ungoogled-chromium";
      homepage = "https://helium.computer";
      license = lib.licenses.gpl3Only;
      mainProgram = "helium-browser";
      platforms = builtins.attrNames platforms;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      maintainers = with lib.maintainers; [ FlameFlag ];
    };
  }
  // (
    if isDarwin then
      {
        sourceRoot = "Helium/Helium.app";

        unpackPhase = ''
          runHook preUnpack
          7zz x "$src" -snld
          runHook postUnpack
        '';

        # Preserve the upstream app bundle's code signature
        dontFixup = true;

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/Applications" "$out/bin"
          cp -R . "$out/Applications/Helium.app"

          makeShellWrapper "$out/Applications/Helium.app/Contents/MacOS/Helium" \
            "$out/bin/helium-browser" ${wrapperFlags}
          ln -s helium-browser "$out/bin/helium"
          runHook postInstall
        '';
      }
    else
      {
        dontUnpack = true;
        dontStrip = true;
        dontWrapQtApps = true;

        buildInputs = linuxDeps ++ [
          adwaita-icon-theme
          gsettings-desktop-schemas
        ];

        installPhase = ''
          runHook preInstall

          payload="$out/libexec/helium"
          launcher="$out/bin/helium-browser"
          desktop="$out/share/applications/helium.desktop"
          mkdir -p "$payload" "$out/bin"
          tar -xJf "$src" -C "$payload" --strip-components=1
          rm -f "$payload/libqt5_shim.so"

          # Use the system Vulkan loader so it can discover the host's drivers
          rm "$payload/libvulkan.so.1"
          ln -s "${lib.getLib vulkan-loader}/lib/libvulkan.so.1" "$payload/libvulkan.so.1"

          # Keep HERE pointing at the payload while shortcuts use our launcher
          substituteInPlace "$payload/helium-wrapper" \
            --replace-fail 'export CHROME_VERSION_EXTRA="custom"' 'export CHROME_VERSION_EXTRA="nix"' \
            --replace-fail 'export CHROME_WRAPPER' "export CHROME_WRAPPER=\"$launcher\""
          install -Dm644 "$payload/helium.desktop" "$desktop"
          substituteInPlace "$desktop" --replace-fail 'Exec=helium' "Exec=$launcher"
          ln -s helium.desktop "$out/share/applications/helium-browser.desktop"
          install -Dm644 "$payload/product_logo_256.png" \
            "$out/share/icons/hicolor/256x256/apps/helium.png"

          makeShellWrapper "$payload/helium-wrapper" "$launcher" \
            ${wrapperFlags} \
            --set CHROME_DESKTOP helium.desktop \
            --set FONTCONFIG_FILE "${fontsConf}" \
            --prefix XDG_DATA_DIRS : "$out/share:${xdgDataDirs}" \
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath linuxDeps}:${driverLink}/lib" \
            --prefix PATH : ${
              lib.makeBinPath [
                coreutils
                xdg-utils
              ]
            } \
            "''${qtWrapperArgs[@]}"
          ln -s helium-browser "$out/bin/helium"

          runHook postInstall
        '';
      }
  )
)
