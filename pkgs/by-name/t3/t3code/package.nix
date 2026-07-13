{
  fetchFromGitHub,
  fetchPnpmDeps,
  lib,
  pnpm_10,
  pnpm_11,
  t3code,
  versionCheckHook,
  channel ? "stable",
}:

let
  sources = lib.importJSON ./sources.json;
  source = sources.${channel} or (throw "t3code: unsupported channel ${channel}");
  pname = if channel == "nightly" then "t3code-nightly" else "t3code";
  pnpm = if channel == "nightly" then pnpm_11 else pnpm_10;
in
t3code.overrideAttrs (
  finalAttrs: previousAttrs: {
    inherit pname;
    version = source.version;

    src = fetchFromGitHub {
      owner = "pingdotgg";
      repo = "t3code";
      tag = source.tag;
      hash = source.srcHash;
    };

    patches = [
      ./patches/0001-add-split-catppuccin-theme-controls.patch
      ./patches/0002-suppress-disabled-desktop-update-surfacing.patch
    ];

    pnpmDeps = fetchPnpmDeps {
      inherit pnpm;
      inherit (finalAttrs)
        pname
        version
        src
        pnpmWorkspaces
        ;

      fetcherVersion = 4;
      hash = source.nodeModulesHash;
    };

    # The nightly channel moved to pnpm 11 while the latest stable release
    # still declares pnpm 10. Replace the pnpm inherited from nixpkgs' stable
    # derivation so dependency installation and the build use the same major.
    nativeBuildInputs = map (
      input: if input == pnpm_10 then pnpm else input
    ) previousAttrs.nativeBuildInputs;

    postFixup = (previousAttrs.postFixup or "") + ''
      wrapProgram "$out/bin/t3code-desktop" \
        --set T3CODE_DISABLE_AUTO_UPDATE 1
    '';

    passthru = (previousAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      upstreamVersion = source.version;
    };

    nativeInstallCheckInputs = (previousAttrs.nativeInstallCheckInputs or [ ]) ++ [
      versionCheckHook
    ];
    doInstallCheck = true;
    versionCheckProgram = "${placeholder "out"}/bin/t3";
    versionCheckProgramArg = "--version";
  }
)
