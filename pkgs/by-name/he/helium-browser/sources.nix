{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.13.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.13.2.1/helium_0.13.2.1_arm64-macos.dmg";
      hash = "sha256-0Vw5iZ4Iro0GHDOOIh5E4cJbVXaqY0edeYGvWDAdw8E=";
    };
  };
  aarch64-linux = {
    version = "0.13.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.13.2.1/helium-0.13.2.1-arm64_linux.tar.xz";
      hash = "sha256-OXRQpFL3rGV+0koZ4ZmYioYuCIxA2/cuOg7P48GmWlI=";
    };
  };
  x86_64-linux = {
    version = "0.13.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.13.2.1/helium-0.13.2.1-x86_64_linux.tar.xz";
      hash = "sha256-OyHIbdEYBByFaENa0WD7WoUzgLryEaT47u8FkT7OY+c=";
    };
  };
}
