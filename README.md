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

#### Using `overlays.default` (recommended)

Composes into your own `nixpkgs`, so the resulting package set inherits your
`config` (e.g. `allowUnfree`) and overlays

```nix
{
  # ...

  outputs = { self, nixpkgs, euvlok-pkgs, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.config.allowUnfree = true;
          nixpkgs.overlays = [ euvlok-pkgs.overlays.default ];

          environment.systemPackages = with pkgs; [ claude-code yt-dlp ];
        })
      ];
    };
  };
}
```

#### Using `legacyPackages`

Note: `legacyPackages` is built from the `nixpkgs` this flake imports with no
`config` applied, so unfree packages will be refused. Prefer `overlays.default`
unless you explicitly want this flake's pinned nixpkgs.

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

#### Cherry-picking a subset

If you only want a few packages in your top-level `pkgs`, wrap `overlays.default`
and `inherit` what you need:

```nix
nixpkgs.overlays = [
  (final: prev: {
    inherit (prev.extend euvlok-pkgs.overlays.default) yt-dlp;
  })
];
```
