{
  fetchurl,
  lib,
  raycast-beta,
}:

let
  source = lib.importJSON ./source.json;
  upstreamVersion = source.version;
in
raycast-beta.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchurl {
      name = "Raycast_Beta.dmg";
      inherit (source) url hash;
    };
  }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      inherit upstreamVersion;
    };
  }
)
