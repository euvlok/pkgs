{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.9.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.9.3.1/helium_0.9.3.1_arm64-macos.dmg";
      hash = "sha256-MH8slWAUs7BiDdV1F847bAhEUmlifZtRYZuvEh5wQ6w=";
    };
  };
  aarch64-linux = {
    version = "0.9.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.3.1/helium-0.9.3.1-arm64.AppImage";
      hash = "sha256-UfYTPdgE4kUIkritmkjGnSQofElmn24nvwZDA8uHdLk=";
    };
  };
  x86_64-linux = {
    version = "0.9.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.3.1/helium-0.9.3.1-x86_64.AppImage";
      hash = "sha256-wUmFmfZPWSvPzArbegegQpY1CFu/XAguqPQpINDE2qY=";
    };
  };
}
