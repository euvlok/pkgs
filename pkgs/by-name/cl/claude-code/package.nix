{ claude-code, fetchzip, fetchNpmDeps }:
let
  version = "2.1.104";
  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-Cjf7xYaIPR0xrwEG91/HIt0/2sU+t2mXbadzP2VFucU=";
  };
in
claude-code.overrideAttrs (oldAttrs: {
  inherit version src;
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace cli.js \
          --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
  '';
  npmDeps = fetchNpmDeps {
    name = "claude-code-${version}-npm-deps";
    inherit src;
    postPatch = ''
      cp ${./package-lock.json} package-lock.json
    '';
    hash = "sha256-VHX8m6kNGCR1DnTrhts6jAq6rmlXFjqyrCHjSVQgCgc=";
  };
  npmDepsHash = "";
})
