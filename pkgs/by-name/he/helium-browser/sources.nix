{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.6.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.6.1/helium_0.10.6.1_arm64-macos.dmg";
      hash = "sha256-SSGLqGeodjk31D1jr/nZaiaMYXFbyrmpvYWodFPIj2E=";
    };
  };
  aarch64-linux = {
    version = "0.10.6.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.6.1/helium-0.10.6.1-arm64.AppImage";
      hash = "sha256-2SDIEni0A3aVqABoaSB7qDyBUfllAc3V6EbGQf+VUAk=";
    };
  };
  x86_64-linux = {
    version = "0.10.6.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.6.1/helium-0.10.6.1-x86_64.AppImage";
      hash = "sha256-6xqNRaP3aqitEseexRVEEjKkJClC0j1HHZoRGQanhSk=";
    };
  };
}
