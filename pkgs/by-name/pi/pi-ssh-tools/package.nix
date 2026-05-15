{
  stdenvNoCC,
  lib,
  openssh,
  tailscale,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-ssh-tools";
  version = "0.1.0";

  src = ./.;

  dontBuild = true;

  postPatch = ''
    substituteInPlace index.ts \
      --replace-fail 'const SSH_COMMAND = "ssh";' \
        'const SSH_COMMAND = "${lib.getExe' openssh "ssh"}";' \
      --replace-fail 'const TAILSCALE_COMMAND = "tailscale";' \
        'const TAILSCALE_COMMAND = "${lib.getExe tailscale}";'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 index.ts "$out/share/pi/extensions/pi-ssh-tools.ts"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 index.ts "$out/bin/pi-ssh-tools.ts"
    runHook postInstall
  '';

  passthru = {
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/pi-ssh-tools.ts";
  };

  meta = {
    description = "pi extension exposing explicit remote tools over Tailscale SSH and OpenSSH";
    homepage = "https://github.com/euvlok/eupkgs";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
