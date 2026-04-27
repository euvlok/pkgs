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
    install -Dm644 extension.ts "$out/share/pi/extensions/agent-statusline.ts"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/agent-statusline.ts";
    inherit agent-statusline;
  };

  meta = {
    description = "pi-mono extension that renders agent-statusline in the built-in footer status area";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
