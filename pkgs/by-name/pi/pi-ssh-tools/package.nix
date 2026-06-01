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
    substituteInPlace src/constants.ts \
      --replace-fail 'export const SSH_COMMAND = "ssh";' \
        'export const SSH_COMMAND = "${lib.getExe' openssh "ssh"}";' \
      --replace-fail 'export const TAILSCALE_COMMAND = "tailscale";' \
        'export const TAILSCALE_COMMAND = "${lib.getExe tailscale}";'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 index.ts "$out/share/pi/extensions/pi-ssh-tools/index.ts"
    cp -R src "$out/share/pi/extensions/pi-ssh-tools/src"
    # NixOS/nix-darwin system profiles link bin/ by default, but not arbitrary
    # share/ subdirectories. Keep a stable profile-visible path for settings.json.
    install -Dm644 index.ts "$out/bin/pi-ssh-tools/index.ts"
    cp -R src "$out/bin/pi-ssh-tools/src"
    runHook postInstall
  '';

  passthru = {
    extensionPath = "${finalAttrs.finalPackage}/share/pi/extensions/pi-ssh-tools";
  };

  meta = {
    description = "pi extension exposing explicit remote tools over Tailscale SSH and OpenSSH";
    homepage = "https://github.com/euvlok/eupkgs";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
