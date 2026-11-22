{
  aldente,
  callPackage,
  fetchurl,
  lib,
}:

let
  source = lib.importJSON ./source.json;
  upstreamVersion = source.version;
in
aldente.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchurl {
      inherit (source) url hash;
    };
  }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = lib.getExe (callPackage ./update.nix { });
      inherit upstreamVersion;
    };
  }
)
