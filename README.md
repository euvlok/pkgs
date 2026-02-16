# EUVlok Pkgs

This is a repo with pkgs meant for [EUVlok](https://github.com/euvlok/euvlok),
although it can be used by other repos as well too

## Usage

### Add as a flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    euvlok-pkgs.url = "github:euvlok/pkgs";
  };
}
```

### Use packages in your configuration

#### Using `legacyPackages`

```nix
{
  # ...

  outputs = { self, nixpkgs, euvlok-pkgs, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          environment.systemPackages = with euvlok-pkgs.legacyPackages.x86_64-linux; [
            helium-browser
            yt-dlp
          ];
        }
      ];
    };
  };
}
```

#### Using in home-manager

```nix
{
  # ...

  outputs = { self, nixpkgs, euvlok-pkgs, home-manager, ... }: {
    homeConfigurations.myUser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        {
          home.packages = with euvlok-pkgs.legacyPackages.x86_64-linux; [
            helium-browser
            yt-dlp
          ];
        }
      ];
    };
  };
}
```

#### Using as an overlay

```nix
{
  # ...

  outputs = { self, nixpkgs, euvlok-pkgs, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ config, pkgs, ... }: {
          nixpkgs.overlays = [
            (final: prev: {
              inherit (euvlok-pkgs.legacyPackages.${prev.system}) yt-dlp
            })
          ];

          environment.systemPackages = with pkgs; [ yt-dlp ];
        })
      ];
    };
  };
}
```
