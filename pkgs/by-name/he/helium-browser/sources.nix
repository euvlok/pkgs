{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.5.1/helium_0.10.5.1_arm64-macos.dmg";
      hash = "sha256-KA4Qz/fh/SfpiEX1mgZU1o7zzlqnFgUQiFAK5KEjmqg=";
    };
  };
  aarch64-linux = {
    version = "0.10.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.5.1/helium-0.10.5.1-arm64.AppImage";
      hash = "sha256-7h0Uvn937RxYol7a50FWHC8n1VEgKy+EHdCAivsMEUo=";
    };
  };
  x86_64-linux = {
    version = "0.10.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.5.1/helium-0.10.5.1-x86_64.AppImage";
      hash = "sha256-c/ea8C1XjTkBo0/ujGHEbKWyCmRMxyuiuOzAO9AMf1o=";
    };
  };
}
