{
  fetchFromGitHub,
  fetchPnpmDeps,
  lib,
  pnpm_11,
  t3code,
  versionCheckHook,
  channel ? "stable",
}:

let
  sources = lib.importJSON ./sources.json;
  source = sources.${channel} or (throw "t3code: unsupported channel ${channel}");
  pname = if channel == "nightly" then "t3code-nightly" else "t3code";
  unwrapped = t3code.unwrapped.overrideAttrs (
    finalAttrs: previousAttrs: {
      pname = "${pname}-unwrapped";
      version = source.version;

      src = fetchFromGitHub {
        owner = "pingdotgg";
        repo = "t3code";
        tag = source.tag;
        hash = source.srcHash;
      };

      patches = [
        ./patches/0002-suppress-disabled-desktop-update-surfacing.patch
      ];

      pnpmDeps = fetchPnpmDeps {
        pnpm = pnpm_11;
        inherit (finalAttrs)
          pname
          version
          src
          pnpmWorkspaces
          ;

        fetcherVersion = 4;
        hash = source.nodeModulesHash;
      };

      postFixup = (previousAttrs.postFixup or "") + ''
        wrapProgram "$out/bin/t3code-desktop" \
          --set T3CODE_DISABLE_AUTO_UPDATE 1
      '';

      nativeInstallCheckInputs = (previousAttrs.nativeInstallCheckInputs or [ ]) ++ [
        versionCheckHook
      ];
      doInstallCheck = true;
      versionCheckProgram = "${placeholder "out"}/bin/t3";
      versionCheckProgramArg = "--version";
    }
  );
in
(t3code.override { t3code-unwrapped = unwrapped; }).overrideAttrs (previousAttrs: {
  inherit pname;
  version = source.version;

  passthru = (previousAttrs.passthru or { }) // {
    updateScript = ./update.sh;
    upstreamVersion = source.version;
  };
})
