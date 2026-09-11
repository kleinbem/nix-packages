#!/usr/bin/env bash
# Update pkgs/buzz-desktop/default.nix to the latest Buzz desktop AppImage.
#
# Vendored-binary package (see the header comment in default.nix) — there's
# no upstream nixpkgs/flake package to bump via flake.lock, so this mirrors
# update-langfuse.sh's sed-and-rehash approach instead of oh-my-pi/antigravity's
# multi-platform versions.json (buzz-desktop ships x86_64-linux only).
#
# Release tags follow the `desktop-vX.Y.Z` pattern (older pre-rename releases
# used bare `vX.Y.Z` and are ignored here — see block/buzz's release history).
#
# Usage:  ./scripts/update-buzz-desktop.sh
# Deps:   bash, curl, jq, nix (nix-prefetch-url, nix hash)
set -euo pipefail

cd "$(dirname "$0")/.."
PKG="pkgs/buzz-desktop/default.nix"

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# ── 1. Latest desktop-v* release ─────────────────────────────────────────────
LATEST=$(curl -fsSL "https://api.github.com/repos/block/buzz/releases" |
  jq -r '[.[] | select(.draft == false and (.tag_name | startswith("desktop-v")))][0].tag_name' |
  sed 's/^desktop-v//')
[[ -n $LATEST && $LATEST != "null" ]] || err "Could not fetch latest desktop-v* release"

CURRENT=$(grep -oP 'version = "\K[^"]+' "$PKG" | head -1)
if [[ $CURRENT == "$LATEST" ]]; then
  log "buzz-desktop already at $LATEST — nothing to do."
  exit 0
fi
log "Updating $CURRENT → $LATEST"

# ── 2. Prefetch the new AppImage's hash ──────────────────────────────────────
URL="https://github.com/block/buzz/releases/download/desktop-v${LATEST}/Buzz_${LATEST}_amd64.AppImage"
log "Prefetching $URL ..."
RAW_HASH=$(nix-prefetch-url --type sha256 "$URL") || err "Could not fetch AppImage — check the URL/naming didn't change: $URL"
HASH=$(nix hash to-sri --type sha256 "$RAW_HASH")
log "Hash: $HASH"

# ── 3. Bump version + hash together (order matters: version drives the URL) ─
sed -i \
  -e "s/version = \"${CURRENT}\";/version = \"${LATEST}\";/" \
  -e "s|hash = \"sha256-[^\"]*\";|hash = \"${HASH}\";|" \
  "$PKG"

# ── 4. Verify ─────────────────────────────────────────────────────────────────
log "Verifying build..."
git add "$PKG"
nix build ".#buzz-desktop" 2>&1 | tail -3
log "Done. buzz-desktop $LATEST ready."
