{
  lib,
  llvmPackages_22,
  makeWrapper,
  stdenvNoCC,
}:

let
  lldb = llvmPackages_22.lldb;
in
stdenvNoCC.mkDerivation {
  pname = "lldb-mcp-launcher";
  version = lldb.version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    makeWrapper '${lib.getExe' lldb "lldb-mcp"}' "$out/bin/lldb-mcp-launcher" \
      --set LLDB_EXE_PATH '${lib.getExe' lldb "lldb"}'

    runHook postInstall
  '';

  meta = {
    description = "Launcher for LLDB's built-in MCP stdio bridge";
    homepage = "https://lldb.llvm.org/use/mcp.html";
    license = lib.licenses.asl20;
    mainProgram = "lldb-mcp-launcher";
    platforms = lib.platforms.unix;
  };
}
