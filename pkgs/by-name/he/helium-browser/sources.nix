{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.11.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.11.2.1/helium_0.11.2.1_arm64-macos.dmg";
      hash = "sha256-jfixNeOiKBznY7lyOpLJscybg7VgEhrf5aI7RBN8DWI=";
    };
  };
  aarch64-linux = {
    version = "0.11.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.2.1/helium-0.11.2.1-arm64.AppImage";
      hash = "sha256-d7+ABYr/AXtxzetTkDoCZ4zOltaY8GFceLHTQ9qAEFc=";
    };
  };
  x86_64-linux = {
    version = "0.11.2.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.11.2.1/helium-0.11.2.1-x86_64.AppImage";
      hash = "sha256-tGOgJSCGrGfkG2aE0VcGm2GH8ttiBQ602GftlWEHRHA=";
    };
  };
}
