# Experimental flake interface to overlay Nixpkgs packages.
# See https://github.com/NixOS/rfcs/pull/49 for details.
{
  description = "EUVlok Packages - overlay for Nixpkgs";

  nixConfig = {
    extra-substituters = [ "https://eupkgs.cachix.org" ];
    extra-trusted-public-keys = [
      "eupkgs.cachix.org-1:V9Y0HdASNNSU9U6EkXhR1j85bZGRtNgW7wSyTiQrwGU="
    ];
  };

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
                bun
                biome
                shellcheck
                gh
                sd
                yamlfmt
                ;
            };

            shellHook = ''
              if [ -f package.json ] && [ -f bun.lock ]; then
                bun install --frozen-lockfile
              fi
            '';
          };
        }
      );

      formatter = forAllSystems (system: self.legacyPackages.${system}.nixfmt);

      apps = forAllSystems (
        system:
        let
          pkgs = self.legacyPackages.${system};
          scripts = pkgs.callPackage ./scripts/build/package.nix { };
        in
        {
          update = {
            type = "app";
            meta.description = "Update packages and verify changed builds";
            program = "${scripts}/bin/update";
          };
          gen-pkg-table = {
            type = "app";
            meta.description = "Regenerate the README package table";
            program = "${scripts}/bin/gen-pkg-table";
          };
          status = {
            type = "app";
            meta.description = "Report local package pin status against nixpkgs master";
            program = "${scripts}/bin/status";
          };
        }
      );
    };
}
