{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.8.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.8.1/helium_0.10.8.1_arm64-macos.dmg";
      hash = "sha256-DWmTwNKtg+1dVbWcbP95Iym0GhUCi+CaeaurNaHBEE8=";
    };
  };
  aarch64-linux = {
    version = "0.10.8.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.8.1/helium-0.10.8.1-arm64.AppImage";
      hash = "sha256-b3r8+Ub960UTlrdDOgZRVw0p2uxUmSO/nM3Hn9wJhF8=";
    };
  };
  x86_64-linux = {
    version = "0.10.8.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.8.1/helium-0.10.8.1-x86_64.AppImage";
      hash = "sha256-pN/Iw1ANggDOxxFb2CN436qbcrs8/bDcEqjZC80grQs=";
    };
  };
}
