{
  stdenvNoCC,
  lib,
  glib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "catppuccin-system-theme-pi";
  version = (lib.importJSON ./package.json).version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./index.ts
      ./src
    ];
  };

  dontBuild = true;

  postPatch = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    substituteInPlace src/system-theme.ts \
      --replace-fail 'execFileAsync("gsettings",' 'execFileAsync("${glib}/bin/gsettings",'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 index.ts "$out/share/pi/extensions/catppuccin-system-theme/index.ts"
    cp -R src "$out/share/pi/extensions/catppuccin-system-theme/src"
    # Keep a profile-visible path without duplicating the extension
    mkdir -p "$out/bin"
    ln -s "$out/share/pi/extensions/catppuccin-system-theme" "$out/bin/catppuccin-system-theme-pi"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/catppuccin-system-theme";
  };

  meta = {
    description = "pi-mono extension that syncs Catppuccin theme with the system color scheme";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
