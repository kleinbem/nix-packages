# mesh-llm, skippy and the skippy native runtimes, re-exported from the
# nixpkgs branch behind NixOS/nixpkgs#571722 (flake input nixpkgs-mesh).
#
# What Martin maintains in nixpkgs is consumed from there, never copied: the
# PR's package.nix files are called against this flake's nixpkgs, so the
# fleet runs exactly the PR. When the PR is in the fleet's nixpkgs, delete
# this directory and the input; the attribute names stay the same.
#
# The scope resolves the packages' references to each other (mesh-llm wants
# skippy-native-runtime, skippy wants both) before falling back to nixpkgs.
{
  lib,
  newScope,
  nixpkgsMesh,
}:
let
  byName = name: "${nixpkgsMesh}/pkgs/by-name/${lib.substring 0 2 name}/${name}/package.nix";
  names = [
    "mesh-llm"
    "mesh-llm-cuda"
    "mesh-llm-rocm"
    "skippy"
    "skippy-native-runtime"
    "skippy-native-runtime-vulkan"
  ];
in
lib.makeScope newScope (self: lib.genAttrs names (name: self.callPackage (byName name) { }))
