{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.12.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.12.4.1/helium_0.12.4.1_arm64-macos.dmg";
      hash = "sha256-0cpES40UjQqUmdmZqEx37SUKJ1F2L4X+91t8+IQ6y5g=";
    };
  };
  aarch64-linux = {
    version = "0.12.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.4.1/helium-0.12.4.1-arm64_linux.tar.xz";
      hash = "sha256-p4aPqMcPA04e5rh9a5WB2FyD1bwfVBR2O2YibkSIIo4=";
    };
  };
  x86_64-linux = {
    version = "0.12.4.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.12.4.1/helium-0.12.4.1-x86_64_linux.tar.xz";
      hash = "sha256-cBqVVImuvEqUeK7QgM5+FB1q4w/cnCcwT8DXPweV4Lg=";
    };
  };
}
