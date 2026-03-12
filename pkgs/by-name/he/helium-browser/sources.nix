{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.2.1/helium_0.10.2.1_arm64-macos.dmg";
      hash = "sha256-TflaAQlgsCB+fgpA9Qbj/5t7x2IMF0gXGCP19Mbyws0=";
    };
  };
  aarch64-linux = {
    version = "0.10.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.2.1/helium-0.10.2.1-arm64.AppImage";
      hash = "sha256-5P1x/e7iOVpfiWz52sTVtr1bAgTOZ7pL2DwChNeWg2I=";
    };
  };
  x86_64-linux = {
    version = "0.10.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.2.1/helium-0.10.2.1-x86_64.AppImage";
      hash = "sha256-Kh6UgdleK+L+G4LNiQL2DkQIwS43cyzX+Jo6K0/fX1M=";
    };
  };
}
