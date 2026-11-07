#!/usr/bin/env bash
# Generic updater for every package here whose passthru.updateScript is
# nix-update-script: the package's own extraArgs say how it updates.
#
# Usage:  ./scripts/update-packages.sh list          # JSON [{attr,args}] for a CI matrix
#         ./scripts/update-packages.sh update <attr> [nix-update args]
#                                                    # bump, build and test one package
# Deps:   bash, jq, nix
set -euo pipefail

cd "$(dirname "$0")/.."
SYSTEM="${SYSTEM:-x86_64-linux}"

list() {
  # Only packages defined in this repo: nix-detour's PR packages carry
  # nixpkgs' updateScript too, but their files live in nixpkgs.
  local self
  self=$(nix flake metadata --json . | jq -r .path)
  # shellcheck disable=SC2016 # Nix, not shell
  nix eval --json ".#legacyPackages.$SYSTEM" --apply '
    ps: builtins.concatMap (n:
      let r = builtins.tryEval (
        let p = ps.${n}; in
        if builtins.isAttrs p && p ? updateScript && builtins.isList p.updateScript
          && builtins.match ".*/bin/nix-update" (builtins.unsafeDiscardStringContext
               (builtins.head p.updateScript)) != null
        then [ {
          attr = n;
          args = builtins.tail p.updateScript;
          position = builtins.unsafeDiscardStringContext (p.meta.position or "");
        } ]
        else [ ]);
      in if r.success then r.value else [ ]) (builtins.attrNames ps)' |
    jq -c --arg self "$self/" \
      '[.[] | select(.position | startswith($self)) | {attr, args}]'
}

update() {
  local attr="$1" entry
  shift
  entry=$(list | jq -c --arg a "$attr" '.[] | select(.attr == $a)')
  [[ -n $entry ]] || {
    echo "no nix-update updateScript for $attr" >&2
    exit 1
  }
  local -a extra
  mapfile -t extra < <(jq -r '.args[]' <<<"$entry")
  nix run --inputs-from . nixpkgs#nix-update -- \
    --flake --system "$SYSTEM" --build --test "${extra[@]}" "$@" "$attr"
}

case "${1:-}" in
list) list ;;
update)
  shift
  update "${1:?attr}" "${@:2}"
  ;;
*)
  echo "usage: $0 list | update <attr>" >&2
  exit 2
  ;;
esac
