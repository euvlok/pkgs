{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.11.3.2";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.11.3.2/helium_0.11.3.2_arm64-macos.dmg";
      hash = "sha256-nOk6FC0g6N1WXLzTxW6mFMu2OO/9TKRqj+nqeOiWi+o=";
    };
  };
  aarch64-linux = {
    version = "0.11.3.2";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.3.2/helium-0.11.3.2-arm64.AppImage";
      hash = "sha256-k9YTB7SFmviS99u5eCiG7PsSCcGHLB350la2cgGKvvA=";
    };
  };
  x86_64-linux = {
    version = "0.11.3.2";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.3.2/helium-0.11.3.2-x86_64.AppImage";
      hash = "sha256-5gdyKg12ZV2hpf0RL+eoJnawuW/J8NobiG+zEA0IOHA=";
    };
  };
}
