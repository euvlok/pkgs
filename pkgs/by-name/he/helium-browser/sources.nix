{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.8.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.8.5.1/helium_0.8.5.1_arm64-macos.dmg";
      hash = "sha256-erlRR3QTHvzNCSXcGtpR27d2ElNrrRvS7ZLHEnZK0wI=";
    };
  };
  aarch64-linux = {
    version = "0.8.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.8.5.1/helium-0.8.5.1-arm64.AppImage";
      hash = "sha256-UUyC19Np3IqVX3NJVLBRg7YXpw0Qzou4pxJURYFLzZ4=";
    };
  };
  x86_64-linux = {
    version = "0.8.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.8.5.1/helium-0.8.5.1-x86_64.AppImage";
      hash = "sha256-jFSLLDsHB/NiJqFmn8S+JpdM8iCy3Zgyq+8l4RkBecM=";
    };
  };
}
