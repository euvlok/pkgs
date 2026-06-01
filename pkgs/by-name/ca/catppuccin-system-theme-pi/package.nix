{
  stdenvNoCC,
  lib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "catppuccin-system-theme-pi";
  version = "0.1.0";
  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 index.ts "$out/share/pi/extensions/catppuccin-system-theme/index.ts"
    cp -R src "$out/share/pi/extensions/catppuccin-system-theme/src"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 index.ts "$out/bin/catppuccin-system-theme-pi/index.ts"
    cp -R src "$out/bin/catppuccin-system-theme-pi/src"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/catppuccin-system-theme";
  };

  meta = {
    description = "pi-mono extension that syncs Catppuccin theme with the system color scheme";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
