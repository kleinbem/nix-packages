#!/usr/bin/env bash
# Update pkgs/oh-my-pi/{default.nix,versions.json} to the latest
# can1357/oh-my-pi GitHub release.
#
# oh-my-pi is vendored as a prebuilt-binary derivation (see
# pkgs/oh-my-pi/default.nix's header comment for why) — upstream publishes
# real GitHub Releases binaries (omp-<platform>-<arch>) rather than requiring
# a build from source. This script re-derives the per-platform hashes
# directly from those release assets and bumps both the `version = "..."`
# literal in default.nix and the versions.json entry it reads from.
#
# Usage:  ./scripts/update-oh-my-pi.sh
# Deps:   bash, curl, jq, nix (nix-prefetch-url, nix hash)
set -euo pipefail

cd "$(dirname "$0")/.."
PKG_DIR="pkgs/oh-my-pi"
DEFAULT_NIX="$PKG_DIR/default.nix"
VERSIONS_JSON="$PKG_DIR/versions.json"

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# ── 1. Latest release ────────────────────────────────────────────────────────
LATEST=$(curl -fsSL "https://api.github.com/repos/can1357/oh-my-pi/releases/latest" |
  jq -r '.tag_name' | sed 's/^v//')
[[ -n $LATEST && $LATEST != "null" ]] || err "Could not fetch latest release"

CURRENT=$(grep -oP 'version = "\K[^"]+' "$DEFAULT_NIX" | head -1)
if [[ $CURRENT == "$LATEST" ]]; then
  log "oh-my-pi already at $LATEST — nothing to do."
  exit 0
fi
log "Updating $CURRENT → $LATEST"

# ── 2. Prefetch each platform's release asset ───────────────────────────────
# nix_os:release-asset-name, per the naming already used in versions.json.
# Ordered array (not an associative array) so output key order stays stable
# across runs.
PLATFORMS=(
  "x86_64-linux:omp-linux-x64"
  "aarch64-linux:omp-linux-arm64"
)

payload="{}"
for p in "${PLATFORMS[@]}"; do
  nix_os="${p%%:*}" asset="${p##*:}"
  url="https://github.com/can1357/oh-my-pi/releases/download/v${LATEST}/${asset}"
  log "  hash $nix_os ..."
  raw=$(nix-prefetch-url --type sha256 "$url")
  hash=$(nix hash to-sri --type sha256 "$raw")
  payload=$(jq --arg k "$nix_os" --arg u "$url" --arg h "$hash" \
    '.[$k]={url:$u,hash:$h}' <<<"$payload")
done

# ── 3. Write back ────────────────────────────────────────────────────────────
tmp=$(mktemp)
jq --arg v "$LATEST" --argjson p "$payload" '.[$v] = $p' "$VERSIONS_JSON" >"$tmp"
mv "$tmp" "$VERSIONS_JSON"

sed -i "s/version = \"${CURRENT}\"/version = \"${LATEST}\"/" "$DEFAULT_NIX"

# ── 4. Verify ────────────────────────────────────────────────────────────────
log "Verifying build..."
nix build ".#oh-my-pi" -L

log "Done. oh-my-pi $LATEST ready."
