{ fetchurl }:
{
  aarch64-darwin = {
    version = "0.9.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/0.9.3.1/helium_0.9.3.1_arm64-macos.dmg";
      hash = "sha256:1b23f0g15bwvc58rnzb2d594823c7g71fxfm1mib1cqlc2ajqzrh";
    };
  };
  aarch64-linux = {
    version = "0.9.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.3.1/helium-0.9.3.1-arm64.AppImage";
      hash = "sha256:1fblhz5h6hq6pwknx7v695y2h94xqr49mbdqj844bqh4v0yi7xji";
    };
  };
  x86_64-linux = {
    version = "0.9.3.1";
    src = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/0.9.3.1/helium-0.9.3.1-x86_64.AppImage";
      hash = "sha256:19nsqk820aglm0p0hp5zbc43b5j2l03pmnqark7jnnagyscqajf1";
    };
  };
}
