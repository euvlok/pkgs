{
  stdenvNoCC,
  lib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "web-search-pi";
  version = (lib.importJSON ./package.json).version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./index.ts
      ./src
    ];
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 index.ts "$out/share/pi/extensions/web-search/index.ts"
    cp -R src "$out/share/pi/extensions/web-search/src"
    # Keep a profile-visible path without duplicating the extension
    mkdir -p "$out/bin"
    ln -s "$out/share/pi/extensions/web-search" "$out/bin/web-search-pi"
    runHook postInstall
  '';

  passthru = {
    # Absolute path consumers can drop into pi-mono `settings.extensions`
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/web-search";
  };

  meta = {
    description = "pi extension that registers an OpenAI-backed web_search tool";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
