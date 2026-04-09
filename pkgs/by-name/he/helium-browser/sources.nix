{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.9.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.9.1/helium_0.10.9.1_arm64-macos.dmg";
      hash = "sha256-qLsd9TNAri8ytp2LyRiRQmCxrvC60r/JYQZCpdEP8es=";
    };
  };
  aarch64-linux = {
    version = "0.10.9.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.9.1/helium-0.10.9.1-arm64.AppImage";
      hash = "sha256-Vvvjcy5UNL6VUn9lXXszKYy+/wlaABahAc+crrB2U1o=";
    };
  };
  x86_64-linux = {
    version = "0.10.9.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.9.1/helium-0.10.9.1-x86_64.AppImage";
      hash = "sha256-FMO4gB2zOjhgmjfE/T0XdDb0NMDKsQFuzy/Org1iD48=";
    };
  };
}
