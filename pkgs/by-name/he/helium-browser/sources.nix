{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.12.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.12.3.1/helium_0.12.3.1_arm64-macos.dmg";
      hash = "sha256-BrbexBlCQh9htQEy4Wiul/oNSn2MVERoqpLT8VRLENM=";
    };
  };
  aarch64-linux = {
    version = "0.12.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.3.1/helium-0.12.3.1-arm64_linux.tar.xz";
      hash = "sha256-GN/k/5mkazNPY1TGOGwJVYdM0YR805/2HHVGY6e1+9c=";
    };
  };
  x86_64-linux = {
    version = "0.12.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.3.1/helium-0.12.3.1-x86_64_linux.tar.xz";
      hash = "sha256-a4kcudN+bsOV253BSmTFsx0Tngmr/jbUd/A1gesc6QE=";
    };
  };
}
