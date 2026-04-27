{
  stdenvNoCC,
  lib,
  claude-statusline,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "claude-statusline-pi";
  version = "0.1.0";
  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 extension.ts "$out/share/pi/extensions/claude-statusline.ts"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`.
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/claude-statusline.ts";
    inherit claude-statusline;
  };

  meta = {
    description = "pi-mono extension that renders claude-statusline as the interactive footer";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
