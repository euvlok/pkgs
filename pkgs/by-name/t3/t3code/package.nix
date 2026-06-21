{
  lib,
  stdenv,
  fetchFromGitHub,
  cctools,
  copyDesktopItems,
  electron_40,
  fetchPnpmDeps,
  installShellFiles,
  libicns,
  makeBinaryWrapper,
  makeDesktopItem,
  node-gyp,
  nodejs_24,
  pnpm_10,
  pnpmBuildHook,
  pnpmConfigHook,
  python3,
  versionCheckHook,
  writeDarwinBundle,
  xcbuild,
  cacert,
  coreutils,
  enableAzureDevOps ? false,
  azure-cli,
  azure-cli-extensions,
  enableBitbucket ? false,
  bitbucket-cli,
  enableClaude ? false,
  claude-code,
  enableCodex ? true,
  codex,
  enableCursor ? false,
  code-cursor,
  enableCursorCli ? false,
  cursor-cli,
  enableGit ? true,
  git,
  enableGitHub ? true,
  gh,
  enableGitLab ? false,
  glab,
  enableJujutsu ? false,
  jujutsu,
  enableOpencode ? false,
  opencode,
  t3code ? null,
  channel ? "stable",
}:

let
  sources = lib.importJSON ./sources.json;
  source = sources.${channel} or (throw "t3code: unsupported channel ${channel}");

  pname = if channel == "nightly" then "t3code-nightly" else "t3code";
  binName = if channel == "nightly" then "t3-nightly" else "t3";
  desktopBinName = if channel == "nightly" then "t3-nightly-desktop" else "t3code-desktop";
  appName = if channel == "nightly" then "T3 Code Nightly (Alpha)" else "T3 Code (Alpha)";
  electron = electron_40;
  nodejs = nodejs_24;
  pnpm = pnpm_10;
  desktopIcon =
    if stdenv.hostPlatform.isDarwin then
      "assets/prod/black-macos-1024.png"
    else
      "assets/prod/black-universal-1024.png";

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    rev = source.rev;
    hash = source.srcHash;
  };

  runtimePackages = [
    coreutils
  ]
  ++ lib.optionals enableAzureDevOps [
    (azure-cli.withExtensions [ azure-cli-extensions.azure-devops ])
  ]
  ++ lib.optionals enableBitbucket [ bitbucket-cli ]
  ++ lib.optionals enableClaude [ claude-code ]
  ++ lib.optionals enableCodex [ codex ]
  ++ lib.optionals enableCursor [ code-cursor ]
  ++ lib.optionals enableCursorCli [ cursor-cli ]
  ++ lib.optionals enableGit [ git ]
  ++ lib.optionals enableGitHub [ gh ]
  ++ lib.optionals enableGitLab [ glab ]
  ++ lib.optionals enableJujutsu [ jujutsu ]
  ++ lib.optionals enableOpencode [ opencode ];

  runtimePathWrapperArgs = lib.optionalString (runtimePackages != [ ]) ''
    \
      --prefix PATH : ${lib.makeBinPath runtimePackages}
  '';
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname src;

  version = source.version;

  strictDeps = true;
  __structuredAttrs = true;
  dontPatchELF = true;
  dontStrip = true;
  noAuditTmpdir = true;

  patches =
    if channel == "stable" then
      [
        ./patches/0001-add-split-catppuccin-theme-controls.patch
        ./patches/0002-suppress-disabled-desktop-update-surfacing.patch
      ]
    else
      [
        ./patches/0003-add-split-catppuccin-theme-controls-nightly.patch
        ./patches/0004-suppress-disabled-desktop-update-surfacing-nightly.patch
      ];

  nativeBuildInputs = [
    cacert
    installShellFiles
    makeBinaryWrapper
    node-gyp
    nodejs
    pnpm
    pnpmBuildHook
    pnpmConfigHook
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools.libtool
    libicns
    writeDarwinBundle
    xcbuild
  ];

  pnpmWorkspaces = [
    # `...` also includes workspace packages depended on by these packages.
    "@t3tools/monorepo"
    "t3..."
    "@t3tools/desktop..."
    "@t3tools/scripts..."
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

  # TODO: remove when pnpmConfigHook supports __structuredAttrs = true.
  # https://github.com/NixOS/nixpkgs/issues/528547
  preConfigure = ''
    __pnpmWorkspaces="''${pnpmWorkspaces[@]}"
    unset pnpmWorkspaces
    declare -g pnpmWorkspaces="$__pnpmWorkspaces"
  '';

  preBuild = ''
    node scripts/update-release-package-versions.ts ${source.version}

    export npm_config_nodedir=${nodejs}
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    # Exclude @t3tools/monorepo from the pending rebuild since vp config needs git.
    pnpm rebuild --pending "''${pnpmInstallFlags[@]}" --filter '!@t3tools/monorepo'
  '';

  pnpmBuildScript = "build:desktop";

  postBuild = ''
    pnpm vp cache clean
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/t3code/apps/desktop" "$out/libexec/t3code/apps/server" "$out/bin"
    cp -R --no-preserve=mode node_modules "$out/libexec/t3code/"
    cp -R --no-preserve=mode apps/server/node_modules apps/server/dist "$out/libexec/t3code/apps/server/"
    cp -R --no-preserve=mode apps/desktop/node_modules apps/desktop/dist-electron "$out/libexec/t3code/apps/desktop/"

    mkdir -p "$out/libexec/t3code/apps/desktop/prod-resources"
    install -m444 ${desktopIcon} "$out/libexec/t3code/apps/desktop/prod-resources/icon.png"

    find "$out/libexec/t3code" -xtype l -delete

    makeWrapper ${lib.getExe nodejs} "$out/bin/${binName}" \
      --add-flags "$out/libexec/t3code/apps/server/dist/bin.mjs" \
      --set-default NODE_ENV production \
      ${runtimePathWrapperArgs}

    makeWrapper ${lib.getExe electron} "$out/bin/${desktopBinName}" \
      --add-flags "$out/libexec/t3code/apps/desktop/dist-electron/main.cjs" \
      --set T3CODE_DISABLE_AUTO_UPDATE 1 \
      --inherit-argv0 ${runtimePathWrapperArgs}

    ${lib.optionalString (channel == "stable") ''
      ln -s ${binName} "$out/bin/t3code"
    ''}

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      mkdir -p "$out/Applications/${appName}.app/Contents/"{MacOS,Resources}
      png2icns "$out/Applications/${appName}.app/Contents/Resources/t3code.icns" ${desktopIcon}

      ${stdenv.shell} ${lib.getExe writeDarwinBundle} \
        "$out" "${appName}" ${desktopBinName} t3code
    ''}

    mkdir -p "$out/share/icons/hicolor/scalable/apps"
    install -m444 ${desktopIcon} "$out/share/icons/t3code.png"
    install -m444 assets/prod/logo.svg "$out/share/icons/hicolor/scalable/apps/t3code.svg"

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    for shell in bash fish zsh; do
      installShellCompletion --cmd ${binName} --"$shell" <("$out/bin/${binName}" --completions "$shell")
    done
  '';

  desktopItems = [
    (makeDesktopItem {
      name = pname;
      desktopName = appName;
      comment = "Minimal web GUI for coding agents";
      exec = "${desktopBinName} %U";
      terminal = false;
      icon = "t3code";
      startupWMClass = "t3code";
      categories = [ "Development" ];
    })
  ];

  passthru = {
    inherit (finalAttrs) pnpmDeps;
    updateScript = ./update.sh;
    upstreamVersion = source.version;
  };

  nativeInstallCheckInputs = [
    versionCheckHook
  ];

  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/${binName}";
  versionCheckProgramArg = "--version";

  meta = {
    description = "Minimal web GUI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ FlameFlag ];
    mainProgram = desktopBinName;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
