# Experimental flake interface to overlay Nixpkgs packages.
# See https://github.com/NixOS/rfcs/pull/49 for details.
{
  description = "EUVlok Packages - overlay for Nixpkgs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = lib.systems.flakeExposed;
      forAllSystems = lib.genAttrs systems;
    in
    {
      /**
        Overlay that adds every package under `pkgs/by-name` to a consumer's
        nixpkgs. Compose this into your own `nixpkgs` overlays list so the
        resulting package set inherits your `config` (e.g. `allowUnfree`)
        rather than being pinned to the nixpkgs this flake imports.
      */
      overlays.default = import ./pkgs/top-level/by-name-overlay.nix {
        baseDirectory = ./pkgs/by-name;
        inherit lib;
      };

      /**
        A nested structure of [packages](https://nix.dev/manual/nix/latest/glossary#package-attribute-set) and other values.

        The "legacy" in `legacyPackages` doesn't imply that the packages exposed
        through this attribute are "legacy" packages. Instead, `legacyPackages`
        is used here as a substitute attribute name for `packages`. The problem
        with `packages` is that it makes operations like `nix flake show`
        nixpkgs unusably slow due to the sheer number of packages the Nix CLI
        needs to evaluate. But when the Nix CLI sees a `legacyPackages`
        attribute it displays `omitted` instead of evaluating all packages,
        which keeps `nix flake show` on Nixpkgs reasonably fast, though less
        information rich.
      */
      legacyPackages = forAllSystems (
        system:
        import ./default.nix {
          inherit system;
          nixpkgsPath = nixpkgs;
        }
      );

      /**
        Development shells for all systems.
      */
      devShells = forAllSystems (
        system:
        let
          pkgs = self.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = builtins.attrValues {
              inherit (pkgs)
                nix-update
                ripgrep
                jq
                gh
                sd
                yamlfmt
                ;
              python3 = pkgs.python3.withPackages (
                ps:
                (builtins.attrValues {
                  inherit (ps)
                    tabulate
                    rich
                    typer
                    cogapp
                    ;
                })
              );
            };
          };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = self.legacyPackages.${system};
          scriptPython = pkgs.python3.withPackages (
            ps:
            (builtins.attrValues {
              inherit (ps)
                tabulate
                rich
                typer
                ;
            })
          );
        in
        {
          update = {
            type = "app";
            meta.description = "Update packages and verify changed builds";
            program = toString (
              pkgs.writeShellScript "update" ''
                export EUPKGS_REPO_ROOT="''${EUPKGS_REPO_ROOT:-$PWD}"
                exec ${scriptPython}/bin/python3 ${self}/scripts/update.py "$@"
              ''
            );
          };
          gen-pkg-table = {
            type = "app";
            meta.description = "Regenerate the README package table";
            program = toString (
              pkgs.writeShellScript "gen-pkg-table" ''
                export EUPKGS_REPO_ROOT="''${EUPKGS_REPO_ROOT:-$PWD}"
                exec ${scriptPython}/bin/python3 ${self}/scripts/gen-pkg-table.py "$@"
              ''
            );
          };
          status = {
            type = "app";
            meta.description = "Report local package pin status against nixpkgs master";
            program = toString (
              pkgs.writeShellScript "status" ''
                export EUPKGS_REPO_ROOT="''${EUPKGS_REPO_ROOT:-$PWD}"
                exec ${scriptPython}/bin/python3 ${self}/scripts/status.py "$@"
              ''
            );
          };
        }
      );
    };
}
