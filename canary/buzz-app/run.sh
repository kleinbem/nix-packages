#!/usr/bin/env bash
# Builds and tests nixpkgs' buzz-app against a block/buzz-app commit (default:
# main), so packaging breakage and dropped workarounds show up before the next
# desktop release reaches nixpkgs.
#
#   NIXPKGS=~/nixpkgs canary/buzz-app/run.sh
#
# NIXPKGS: a nixpkgs checkout with buzz-app (kleinbem/nixpkgs@buzz-app-next).
# BUZZ_APP_REV: the commit to build (default: main).
set -euo pipefail

nixpkgs="$(realpath "${NIXPKGS:?set NIXPKGS to a nixpkgs checkout}")"
here="$(dirname "$(realpath "$0")")"
rev="${BUZZ_APP_REV:-$(git ls-remote https://github.com/block/buzz-app refs/heads/main | cut -f1)}"
echo "buzz-app $rev"

args=(--arg nixpkgs "$nixpkgs" --argstr rev "$rev")

# The dependency hashes change with the commit: build each fetcher once with an
# empty hash and take the one Nix reports.
learn_hash() {
  local hash
  hash="$(
    (nix-build "$here" "${args[@]}" -A "$1" --no-out-link 2>&1 || true) |
      sed -n 's/^ *got: *//p' | tail -n 1
  )"
  if [[ -z $hash ]]; then
    echo "could not determine the hash of $1" >&2
    nix-build "$here" "${args[@]}" -A "$1" --no-out-link
    exit 1
  fi
  echo "$hash"
}
args+=(--argstr cargoHash "$(learn_hash cargoDeps)")
args+=(--argstr pnpmHash "$(learn_hash pnpmDeps)")

# The build runs upstream's test suite and the package's install checks.
nix-build "$here" "${args[@]}" -A buzz-app --no-out-link
