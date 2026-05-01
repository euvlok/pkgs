{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.11.7.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.11.7.1/helium_0.11.7.1_arm64-macos.dmg";
      hash = "sha256-jbu/w3/GYC60Gs0ueeECrbeDDSLAoXFManquIpw0VvM=";
    };
  };
  aarch64-linux = {
    version = "0.11.7.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.7.1/helium-0.11.7.1-arm64.AppImage";
      hash = "sha256-OfI7oDveklNmKef9u8RHInbKT+jldaXMDgs8BSdiaUs=";
    };
  };
  x86_64-linux = {
    version = "0.11.7.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.7.1/helium-0.11.7.1-x86_64.AppImage";
      hash = "sha256-qzc135IP5F2btxtOMUGMz+0azJhYL9KI0lcPG2KjcxU=";
    };
  };
}
