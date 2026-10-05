#!/usr/bin/env bash
# Update pkgs/buzz-desktop to the latest block/buzz `desktop-vX.Y.Z` release.
#
# buzz-desktop is built from source at the release tag (see
# pkgs/buzz-desktop/default.nix). nix-update bumps the version and every hash
# in one pass: the source, the desktop's own Cargo vendor hash, the pnpm
# dependency hash, and — via `--subpackage sidecars` — the sidecars' workspace
# Cargo vendor hash in sidecars.nix. Same command as the package's
# passthru.updateScript, so it stays in sync with the nixpkgs package (#569165).
#
# Usage:  ./scripts/update-buzz-desktop.sh
# Deps:   bash, git, nix (runs nix-update from this flake's nixpkgs)
#         GITHUB_TOKEN is honoured by nix-update for API rate limits.
set -euo pipefail

cd "$(dirname "$0")/.."

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }

CURRENT=$(nix eval --raw .#buzz-desktop.version)

nix run --inputs-from . nixpkgs#nix-update -- \
  --flake buzz-desktop \
  --version-regex 'desktop-v(.*)' \
  --subpackage sidecars

LATEST=$(nix eval --raw .#buzz-desktop.version)
if [[ $CURRENT == "$LATEST" ]]; then
  log "buzz-desktop already at $LATEST — nothing to do."
  exit 0
fi
log "Updated $CURRENT → $LATEST"

# Stage so the flake sees the edits, then build the full app (including sidecars).
git add pkgs/buzz-desktop
log "Verifying build..."
nix build .#buzz-desktop --no-link --print-build-logs 2>&1 | tail -5
log "Done. buzz-desktop $LATEST ready."
