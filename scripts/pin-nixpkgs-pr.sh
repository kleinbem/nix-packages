#!/usr/bin/env bash
# Usage: scripts/pin-nixpkgs-pr.sh NAME REV
#
# Pins the nixpkgs-prs.json entry NAME to commit REV (a full SHA) of its
# repository and records the commit's narHash. Pin only a commit whose
# packages are green on nixpkgs-review-gha: whatever is pinned here reaches
# the fleet. A new entry is added to nixpkgs-prs.json by hand first.
set -euo pipefail

name="$1" rev="$2"
file="$(dirname "$(realpath "$0")")/../nixpkgs-prs.json"

if [[ ! $rev =~ ^[0-9a-f]{40}$ ]]; then
  echo "REV must be a full 40-character commit SHA" >&2
  exit 1
fi
if ! jq -e --arg n "$name" 'has($n)' "$file" >/dev/null; then
  echo "nixpkgs-prs.json has no entry $name" >&2
  exit 1
fi

source=$(jq -r --arg n "$name" '.[$n] | "github:\(.owner)/\(.repo)"' "$file")
narHash=$(nix flake prefetch --json "$source/$rev" | jq -r .hash)

tmp=$(mktemp)
jq --indent 2 --arg n "$name" --arg rev "$rev" --arg h "$narHash" \
  '.[$n].rev = $rev | .[$n].narHash = $h' "$file" >"$tmp"
mv "$tmp" "$file"
echo "$name pinned to $rev ($narHash)"
