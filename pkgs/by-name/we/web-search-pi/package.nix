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
    install -Dm644 index.ts "$out/share/pi/extensions/web-search/index.ts"
    cp -R src "$out/share/pi/extensions/web-search/src"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 index.ts "$out/bin/web-search-pi/index.ts"
    cp -R src "$out/bin/web-search-pi/src"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/web-search";
  };

  meta = {
    description = "pi extension that registers an OpenAI-backed web_search tool";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
