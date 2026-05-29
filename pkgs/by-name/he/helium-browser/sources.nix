{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.12.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.12.5.1/helium_0.12.5.1_arm64-macos.dmg";
      hash = "sha256-uws6OUTyV6/Ejo1FqFnpNSG3tTUGFMNelrex2m1Ymd0=";
    };
  };
  aarch64-linux = {
    version = "0.12.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.5.1/helium-0.12.5.1-arm64_linux.tar.xz";
      hash = "sha256-q6cCrvDh9eYQZwCLArKXZDpYkl0Zzi2g9gp9l+G+QIA=";
    };
  };
  x86_64-linux = {
    version = "0.12.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.5.1/helium-0.12.5.1-x86_64_linux.tar.xz";
      hash = "sha256-tfiy1MkxXq9vOjp57R3ykHjleG0Viz/C2ttwXbHnPwA=";
    };
  };
}
