{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.4.1/helium_0.10.4.1_arm64-macos.dmg";
      hash = "sha256-N33dpa3lj24t09/gvY+5pXNQVeNXKhaZlwZEz1eP9V4=";
    };
  };
  aarch64-linux = {
    version = "0.10.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.4.1/helium-0.10.4.1-arm64.AppImage";
      hash = "sha256-pLyTS69sPs8j7zALwc3yQ74/3ZHw1G9aebxGcjtBU/I=";
    };
  };
  x86_64-linux = {
    version = "0.10.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.4.1/helium-0.10.4.1-x86_64.AppImage";
      hash = "sha256-JjNtf5UoGIQ8fkHqsWAERmKRLc3FKIr11fnoRhuZCSQ=";
    };
  };
}
