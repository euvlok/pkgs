{ callPackage, lib, ... }:
let
  by-name-overlay = import ./top-level/by-name-overlay.nix {
    baseDirectory = ./by-name;
    inherit lib;
  };
  pkgs = lib.fix (
    lib.extends by-name-overlay (_: {
      inherit callPackage;
    })
  );
in
pkgs
