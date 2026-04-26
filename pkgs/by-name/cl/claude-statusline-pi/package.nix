{ stdenvNoCC, lib, claude-statusline }:

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
    # The wrapped binary, exposed for convenience.
    inherit claude-statusline;
  };

  meta = {
    description = "pi-mono extension that renders claude-statusline as the interactive footer";
    longDescription = ''
      Provides a TypeScript pi-mono extension that spawns the
      `claude-statusline` binary with a Claude-Code-shaped JSON payload built
      from the active session, captures its rendered output, and installs it
      as a custom footer via `ctx.ui.setFooter`.

      Add the path exposed at `${"\${claude-statusline-pi.extensionPath}"}`
      (or directly at $out/share/pi/extensions/claude-statusline.ts) to your
      pi-mono `settings.extensions` array.
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
