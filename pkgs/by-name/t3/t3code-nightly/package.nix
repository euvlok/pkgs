{ callPackage, path }:

callPackage ../t3code/package.nix {
  channel = "nightly";
  t3code = callPackage (path + "/pkgs/by-name/t3/t3code/package.nix") { };
}
