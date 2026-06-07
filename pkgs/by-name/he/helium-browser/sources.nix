{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.13.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.13.1.1/helium_0.13.1.1_arm64-macos.dmg";
      hash = "sha256-oB2aJQcE5FtSDlxEp+lZ58K3HX/EeAXOq5K3w/m4qz8=";
    };
  };
  aarch64-linux = {
    version = "0.13.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.13.1.1/helium-0.13.1.1-arm64_linux.tar.xz";
      hash = "sha256-Sq7Iae93/t98uyLyDgRtEX+7n+Hc4MssZqg9n5bzNC8=";
    };
  };
  x86_64-linux = {
    version = "0.13.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.13.1.1/helium-0.13.1.1-x86_64_linux.tar.xz";
      hash = "sha256-MXV5LVknmxhYPq5+W6O2QYz3bemw1nxLs4kI+pS3Mgs=";
    };
  };
}
