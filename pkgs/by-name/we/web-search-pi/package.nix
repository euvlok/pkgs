{
  stdenvNoCC,
  lib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "web-search-pi";
  version = "0.1.0";
  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 extension.ts "$out/share/pi/extensions/web-search.ts"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 extension.ts "$out/bin/web-search-pi.ts"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/web-search.ts";
  };

  meta = {
    description = "pi-mono extension that enables and displays Responses web search calls";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
