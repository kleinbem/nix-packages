#!/usr/bin/env bash
# Usage: scripts/nixpkgs-prs-merged.sh
#
# Prints the nixpkgs-prs.json entries whose packages are all in this flake's
# nixpkgs in the same or a newer version than the pinned ones: their PR has
# reached the channel, so the entry can go and nixpkgs' packages take over.
# Run from the repository root.
set -euo pipefail

# shellcheck disable=SC2016  # a Nix expression, expanded by Nix
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    system = "x86_64-linux";
    nixpkgs = import flake.inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    ours = flake.legacyPackages.${system};
    registry = builtins.fromJSON (builtins.readFile ./nixpkgs-prs.json);
    inNixpkgs =
      attr:
      nixpkgs ? ${attr}
      && builtins.compareVersions nixpkgs.${attr}.version ours.${attr}.version >= 0;
    merged = builtins.filter (name: builtins.all inNixpkgs registry.${name}.attrs) (
      builtins.attrNames registry
    );
  in
  builtins.concatStringsSep "\n" merged
'
