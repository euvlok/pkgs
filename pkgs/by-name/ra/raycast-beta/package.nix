{
  raycast,
  fetchurl,
  lib,
  ...
}:

let
  source = lib.importJSON ./source.json;
in
raycast.overrideAttrs (
  previousAttrs:
  lib.optionalAttrs (lib.versionOlder previousAttrs.version source.version) {
    inherit (source) version;
    src = fetchurl {
      inherit (source) url hash;
    };
  }
  // {
    passthru = (previousAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      upstreamVersion = source.version;
    };
  }
)
