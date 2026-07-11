{
  claude-code,
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  manifest = lib.importJSON ./source.json;
  upstreamVersion = manifest.version;
  baseUrl = "https://downloads.claude.ai/claude-code-releases";
  platformKey = "${stdenvNoCC.hostPlatform.node.platform}-${stdenvNoCC.hostPlatform.node.arch}";
  platformManifestEntry =
    manifest.platforms.${platformKey}
      or (throw "claude-code: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
claude-code.overrideAttrs (
  prevAttrs:
  lib.optionalAttrs (lib.versionOlder prevAttrs.version upstreamVersion) {
    version = upstreamVersion;
    src = fetchurl {
      url = "${baseUrl}/${upstreamVersion}/${platformKey}/claude";
      sha256 = platformManifestEntry.checksum;
    };
  }
  // {
    passthru = (prevAttrs.passthru or { }) // {
      updateScript = ./update.sh;
      inherit upstreamVersion;
    };
  }
)
