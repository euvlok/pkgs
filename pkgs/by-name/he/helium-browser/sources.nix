{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.11.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.11.5.1/helium_0.11.5.1_arm64-macos.dmg";
      hash = "sha256-P5iXtXS05uu5Qy9jPheXAbjewn6jKTcqc5uF2yZoz/k=";
    };
  };
  aarch64-linux = {
    version = "0.11.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.5.1/helium-0.11.5.1-arm64.AppImage";
      hash = "sha256-f3nTqFVlgOIObtvtA41w17zcguaxjc54I59anCPoM38=";
    };
  };
  x86_64-linux = {
    version = "0.11.5.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.5.1/helium-0.11.5.1-x86_64.AppImage";
      hash = "sha256-Ni7IZ9UBafr+ss0BcQaRKqmlmJI4IV1jRAJ8jhcodlg=";
    };
  };
}
