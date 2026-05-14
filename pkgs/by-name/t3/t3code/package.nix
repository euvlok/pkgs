{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  cctools,
  copyDesktopItems,
  electron_40,
  installShellFiles,
  libicns,
  nodejs_24,
  makeBinaryWrapper,
  makeDesktopItem,
  node-gyp,
  python3,
  writableTmpDirAsHomeHook,
  writeDarwinBundle,
  xcbuild,
  jq,
  versionCheckHook,
  gh,
  coreutils,
  git,
  openssh,
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

  nodeModules = stdenvNoCC.mkDerivation {
    pname = "${pname}-node_modules";
    version = source.version;
    inherit src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    dontFixup = true;
    dontPatchShebangs = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)

      bun install \
        --cpu="*" \
        --force \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress \
        --os="*"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      find . -type d -name node_modules -prune -exec cp -R --parents {} "$out" \;

      runHook postInstall
    '';

    outputHash = source.nodeModulesHash;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };
in
stdenv.mkDerivation (finalAttrs: {
  inherit
    pname
    src
    nodeModules
    ;

  version = source.version;

  nativeBuildInputs = [
    bun
    jq
    installShellFiles
    makeBinaryWrapper
    node-gyp
    nodejs
    python3
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools.libtool
    libicns
    writeDarwinBundle
    xcbuild
  ];

  strictDeps = true;
  __structuredAttrs = true;
  dontPatchELF = true;
  dontStrip = true;
  noAuditTmpdir = true;

  patches = [
    ./patches/0001-add-split-catppuccin-theme-controls.patch
    ./patches/0002-remove-desktop-update-surfacing.patch
    ./patches/0003-add-made-in-eu-composer-badge.patch
  ];

  postPatch = ''
    for packageJson in \
      apps/server/package.json \
      apps/desktop/package.json \
      apps/web/package.json \
      packages/contracts/package.json
    do
      jq '.version = "${source.version}"' "$packageJson" > "$packageJson.tmp"
      mv "$packageJson.tmp" "$packageJson"
    done
  '';

  configurePhase = ''
    runHook preConfigure

    cp -R ${finalAttrs.nodeModules}/node_modules node_modules
    [ -d ${finalAttrs.nodeModules}/apps ] && cp -R ${finalAttrs.nodeModules}/apps/. apps/
    [ -d ${finalAttrs.nodeModules}/packages ] && cp -R ${finalAttrs.nodeModules}/packages/. packages/
    [ -d ${finalAttrs.nodeModules}/scripts ] && cp -R ${finalAttrs.nodeModules}/scripts/. scripts/
    [ -d ${finalAttrs.nodeModules}/oxlint-plugin-t3code ] && cp -R ${finalAttrs.nodeModules}/oxlint-plugin-t3code/. oxlint-plugin-t3code/
    chmod -R u+rw node_modules apps/*/node_modules packages/*/node_modules scripts/node_modules oxlint-plugin-t3code/node_modules 2>/dev/null || true
    patchShebangs node_modules apps/*/node_modules packages/*/node_modules scripts/node_modules oxlint-plugin-t3code/node_modules 2>/dev/null || true

    export npm_config_nodedir=${nodejs}
    cd node_modules/.bun/node-pty@*/node_modules/node-pty
    node-gyp rebuild
    node scripts/post-install.js
    cd -

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    export PATH="$PWD/node_modules/.bin:$PATH"
    # Vite resolves the dev-server/HMR host while loading config, even for
    # production builds. Darwin sandboxes do not always provide a localhost
    # hosts entry, so use the numeric loopback address to keep builds pure.
    export HOST=127.0.0.1

    bun run --cwd apps/web build
    bun run --cwd apps/server build
    bun run --cwd apps/desktop build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/t3code/apps/desktop" "$out/libexec/t3code/apps/server" "$out/bin"
    cp -R --no-preserve=mode node_modules "$out/libexec/t3code/"
    cp -R --no-preserve=mode apps/server/node_modules apps/server/dist "$out/libexec/t3code/apps/server/"
    cp -R --no-preserve=mode apps/desktop/node_modules apps/desktop/dist-electron "$out/libexec/t3code/apps/desktop/"

    # node-pty launches POSIX shells via its spawn-helper executable. The
    # --no-preserve=mode copies above normalize it to non-executable; restore
    # it before the output becomes read-only in the Nix store.
    find "$out/libexec/t3code" -path '*/node-pty/*/spawn-helper' -exec chmod 755 {} +
    find "$out/libexec/t3code" -path '*/node-pty/*/pty.node' -exec chmod 644 {} +

    mkdir -p "$out/libexec/t3code/apps/desktop/prod-resources"
    install -m444 ${desktopIcon} "$out/libexec/t3code/apps/desktop/prod-resources/icon.png"

    find "$out/libexec/t3code" -xtype l -delete

    makeWrapper ${lib.getExe nodejs} "$out/bin/${binName}" \
      --add-flags "$out/libexec/t3code/apps/server/dist/bin.mjs" \
      --set-default NODE_ENV production \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          git
          gh
          openssh
        ]
      }

    makeWrapper ${lib.getExe electron} "$out/bin/${desktopBinName}" \
      --add-flags "$out/libexec/t3code/apps/desktop/dist-electron/main.cjs" \
      --set T3CODE_DISABLE_AUTO_UPDATE 1 \
      --inherit-argv0

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
    inherit nodeModules;
    updateScript = ./update.sh;
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
