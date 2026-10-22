#!/usr/bin/env bash
# Builds nixpkgs' Buzz packages against a Buzz commit (default: main), so
# packaging breakage shows up before the next desktop release reaches nixpkgs.
#
#   NIXPKGS=~/nixpkgs canary/buzz/run.sh [attr...]
#
# NIXPKGS: a nixpkgs checkout with the Buzz packages (kleinbem/nixpkgs@buzz-next).
# BUZZ_REV: the Buzz commit to build (default: main).
# attrs: what to build (default: every package, their tests and the NixOS test).
set -euo pipefail

nixpkgs="$(realpath "${NIXPKGS:?set NIXPKGS to a nixpkgs checkout}")"
here="$(dirname "$(realpath "$0")")"
rev="${BUZZ_REV:-$(git ls-remote https://github.com/block/buzz refs/heads/main | cut -f1)}"
echo "Buzz $rev"

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
args+=(--argstr workspaceCargoHash "$(learn_hash workspaceCargoDeps)")
args+=(--argstr desktopCargoHash "$(learn_hash desktopCargoDeps)")
args+=(--argstr desktopPnpmHash "$(learn_hash buzz-desktop.pnpmDeps)")
args+=(--argstr relayWebPnpmHash "$(learn_hash buzz-relay.web.pnpmDeps)")

if (($# == 0)); then
  set -- buzz-cli buzz-agent buzz-dev-mcp git-credential-nostr git-sign-nostr buzz-acp \
    buzz-backend-kubernetes buzz-relay buzz-desktop tests nixos
fi
attrs=()
for attr in "$@"; do
  attrs+=(-A "$attr")
done
nix-build "$here" "${args[@]}" "${attrs[@]}" --no-out-link --keep-going
