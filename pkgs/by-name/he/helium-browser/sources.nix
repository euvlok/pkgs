{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.13.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.13.3.1/helium_0.13.3.1_arm64-macos.dmg";
      hash = "sha256-4SeQxbnd9nFtWvUOFPbEFgFs1LFongXaA02UI2qfdnA=";
    };
  };
  aarch64-linux = {
    version = "0.13.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.13.3.1/helium-0.13.3.1-arm64_linux.tar.xz";
      hash = "sha256-DSlJxzRAFhTkTyYFyUrypf+leU+Sip2pkLtOuyIduzU=";
    };
  };
  x86_64-linux = {
    version = "0.13.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.13.3.1/helium-0.13.3.1-x86_64_linux.tar.xz";
      hash = "sha256-R/cGyWuBrLeFhucrpkRpQN9k/MWN3JlnwSufEsqVkmY=";
    };
  };
}
