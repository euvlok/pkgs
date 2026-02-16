{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.9.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.9.1.1/helium_0.9.1.1_arm64-macos.dmg";
      hash = "sha256:0gyfl8mv6f60mj81viyj7hkyvmfjlzgaj9f54ycnx5dxcwhh78m8";
    };
  };
  aarch64-linux = {
    version = "0.9.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.1.1/helium-0.9.1.1-arm64.AppImage";
      hash = "sha256:069hrxsdjxfdvpy6332m18ai3w4cc5pm76v3ilizn978m9rn4zhq";
    };
  };
  x86_64-linux = {
    version = "0.9.1.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.1.1/helium-0.9.1.1-x86_64.AppImage";
      hash = "sha256:08dqsj1cy6qzwvxvzcvlfzsbsz02k2wdmymrqkwdq69miqm3rb6h";
    };
  };
}
