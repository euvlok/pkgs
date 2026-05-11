{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.12.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.12.1.1/helium_0.12.1.1_arm64-macos.dmg";
      hash = "sha256-JLziPZ1Hl0WMpOgN5eliSeAjw/NQhtURQZvqWdQdJyk=";
    };
  };
  aarch64-linux = {
    version = "0.12.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.1.1/helium-0.12.1.1-arm64_linux.tar.xz";
      hash = "sha256-DxFgHHGlvzLo/UdpaCAx5trKwY6APFyH8FhRPaaCtME=";
    };
  };
  x86_64-linux = {
    version = "0.12.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.1.1/helium-0.12.1.1-x86_64_linux.tar.xz";
      hash = "sha256-LQTffKZUf5HMm/Dgy8UlbLtGldz3ptQm2qPx4fXzY54=";
    };
  };
}
