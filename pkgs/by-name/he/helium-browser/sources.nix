{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.10.7.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.10.7.1/helium_0.10.7.1_arm64-macos.dmg";
      hash = "sha256-zQUIP9LoZnjPKyvxPAOmyOsNp/cr0EBSxX0YEdmJO58=";
    };
  };
  aarch64-linux = {
    version = "0.10.7.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.7.1/helium-0.10.7.1-arm64.AppImage";
      hash = "sha256-ZE7AI7rh68/ogjO+MpUmF0Gc0n/6THnnloR2kFj7HeY=";
    };
  };
  x86_64-linux = {
    version = "0.10.7.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.10.7.1/helium-0.10.7.1-x86_64.AppImage";
      hash = "sha256-+vmxXcg8TkR/GAiHKnjq4b04bGtQzErfJkOb4P4nZUk=";
    };
  };
}
