{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.9.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.9.4.1/helium_0.9.4.1_arm64-macos.dmg";
      hash = "sha256-miPsputiNQwAm867O5I+OBZAr52OzzIFD1UHMzWDMVQ=";
    };
  };
  aarch64-linux = {
    version = "0.9.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.4.1/helium-0.9.4.1-arm64.AppImage";
      hash = "sha256-BvU0bHtJMd6e09HY+9Vhycr3J0O2hunRJCHXpzKF8lk=";
    };
  };
  x86_64-linux = {
    version = "0.9.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.4.1/helium-0.9.4.1-x86_64.AppImage";
      hash = "sha256-N5gdWuxOrIudJx/4nYo4/SKSxakpTFvL4zzByv6Cnug=";
    };
  };
}
