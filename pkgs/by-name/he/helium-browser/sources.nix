{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.9.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.9.2.1/helium_0.9.2.1_arm64-macos.dmg";
      hash = "sha256:1abjr5jwfc3ann0bdrnphfmi8imxaj3xv999n18jkzqp9fmw3mqf";
    };
  };
  aarch64-linux = {
    version = "0.9.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.2.1/helium-0.9.2.1-arm64.AppImage";
      hash = "sha256:0ppb3v4jvmzvscmx240f2blcffh75qr7ay5z82al73f2bm6ff4jx";
    };
  };
  x86_64-linux = {
    version = "0.9.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.2.1/helium-0.9.2.1-x86_64.AppImage";
      hash = "sha256:1z4vz3imvvzh258pqn6xbfbgmxlnaz2rxcrmnq33sf0dpwic3q42";
    };
  };
}
