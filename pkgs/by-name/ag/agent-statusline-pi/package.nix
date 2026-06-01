{
  stdenvNoCC,
  lib,
  agent-statusline,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "agent-statusline-pi";
  version = "0.1.0";
  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 index.ts "$out/share/pi/extensions/agent-statusline/index.ts"
    cp -R src "$out/share/pi/extensions/agent-statusline/src"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 index.ts "$out/bin/agent-statusline-pi/index.ts"
    cp -R src "$out/bin/agent-statusline-pi/src"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/agent-statusline";
    inherit agent-statusline;
  };

  meta = {
    description = "pi-mono extension that renders agent-statusline in the built-in footer status area";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
