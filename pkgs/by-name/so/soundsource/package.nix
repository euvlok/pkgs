{
  fetchzip,
  lib,
  soundsource,
}:
let
  source = lib.importJSON ./source.json;
  upstreamVersion = source.version;
in
soundsource.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchzip {
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
