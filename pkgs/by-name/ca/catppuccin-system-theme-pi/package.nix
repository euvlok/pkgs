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
    install -Dm644 extension.ts "$out/share/pi/extensions/catppuccin-system-theme.ts"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 extension.ts "$out/bin/catppuccin-system-theme-pi.ts"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/catppuccin-system-theme.ts";
  };

  meta = {
    description = "pi-mono extension that syncs Catppuccin theme with the system color scheme";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
