{
  lib,
  nix-update-script,
  t3code,
  versionCheckHook,
  channel ? "stable",
}:

let
  sourceFile =
    if channel == "stable" then
      ./stable.json
    else if channel == "nightly" then
      ../t3code-nightly/source.json
    else
      throw "t3code: unsupported channel ${channel}";
  source = lib.importJSON sourceFile;
  pname = if channel == "nightly" then "t3code-nightly" else "t3code";
  unwrapped = t3code.unwrapped.overrideAttrs (previousAttrs: {
    pname = "${pname}-unwrapped";
    inherit (source) version;

    # Nixpkgs derives the GitHub tag from the package version
    src = previousAttrs.src.override { hash = source.srcHash; };
    pnpmDeps = previousAttrs.pnpmDeps.override { hash = source.nodeModulesHash; };

    patches = (previousAttrs.patches or [ ]) ++ [
      ./patches/0002-suppress-disabled-desktop-update-surfacing.patch
    ];

    # pnpmConfigHook patches root shims only
    preBuild = (previousAttrs.preBuild or "") + ''
      patchShebangs apps/*/node_modules packages/*/node_modules scripts/node_modules
    '';

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
  });
in
(t3code.override { t3code-unwrapped = unwrapped; }).overrideAttrs (previousAttrs: {
  inherit pname;

  passthru = (previousAttrs.passthru or { }) // {
    updateScript = {
      command = nix-update-script {
        extraArgs = [
          "--use-github-releases"
          "--override-filename"
          (toString sourceFile)
          "--version-regex"
          (
            if channel == "nightly" then
              "v([0-9]+\\.[0-9]+\\.[0-9]+-nightly\\.[0-9]{8}\\.[0-9]+)$"
            else
              "v([0-9]+\\.[0-9]+\\.[0-9]+)$"
          )
        ]
        ++ lib.optional (channel == "nightly") "--version=unstable";
      };
      attrPath = "${pname}.unwrapped";
    };
    upstreamVersion = source.version;
  };
})
