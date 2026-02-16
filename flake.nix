# Experimental flake interface to overlay Nixpkgs packages.
# See https://github.com/NixOS/rfcs/pull/49 for details.
{
  description = "EUVlok Packages - overlay for Nixpkgs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = lib.systems.flakeExposed;
      forAllSystems = lib.genAttrs systems;
    in
    {
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
                sd
                ;
            };
          };
        }
      );
    };
}
