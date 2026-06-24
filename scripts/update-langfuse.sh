#!/usr/bin/env bash
# Update pkgs/langfuse/default.nix to the latest Langfuse release.
#
# Langfuse releases roughly 2x per week. This script:
#   1. Queries GitHub for the latest release tag.
#   2. Zeroes the source hash, runs nix build, parses the "got:" hash.
#   3. Checks if the pnpm major version changed and updates pnpm_NN.
#   4. Zeroes the pnpm deps hash, runs nix build again, parses the "got:" hash.
#   5. Verifies the full build succeeds.
#
# Usage:  ./scripts/update-langfuse.sh
# Deps:   bash, curl, jq, nix, python3
set -euo pipefail

cd "$(dirname "$0")/.."
PKG="pkgs/langfuse/default.nix"
FAKE="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# Replace the Nth occurrence (1-indexed) of `hash = "sha256-..."` in $PKG.
set_hash() {
  local n="$1" value="$2"
  python3 - "$PKG" "$n" "$value" <<'PY'
import sys, re
path, n, value = sys.argv[1], int(sys.argv[2]), sys.argv[3]
text = open(path).read()
pattern = r'hash = "sha256-[^"]*"'
matches = list(re.finditer(pattern, text))
if len(matches) < n:
    print(f"ERROR: only {len(matches)} hash= lines found, wanted index {n}", file=sys.stderr)
    sys.exit(1)
m = matches[n - 1]
open(path, 'w').write(text[:m.start()] + f'hash = "{value}"' + text[m.end():])
PY
}

# Run nix build and extract the "got:" hash from the mismatch error.
# Must git-add first: Nix evaluates from the git index, not the working tree.
extract_hash() {
  git add "$PKG"
  nix build ".#langfuse" 2>&1 | grep -oP '(?<=got:    )sha256-\S+' | head -1
}

# ── 1. Latest release ────────────────────────────────────────────────────────
LATEST=$(curl -fsSL "https://api.github.com/repos/langfuse/langfuse/releases/latest" |
  jq -r '.tag_name' | sed 's/^v//')
[[ -n $LATEST && $LATEST != "null" ]] || err "Could not fetch latest release"

CURRENT=$(grep -oP 'version = "\K[^"]+' "$PKG" | head -1)
if [[ $CURRENT == "$LATEST" ]]; then
  log "Langfuse already at $LATEST — nothing to do."
  exit 0
fi
log "Updating $CURRENT → $LATEST"

# ── 2. Bump version, discover source hash ───────────────────────────────────
sed -i "s/version = \"${CURRENT}\"/version = \"${LATEST}\"/" "$PKG"
set_hash 1 "$FAKE"

log "Fetching source hash..."
SRC_HASH=$(extract_hash)
[[ -n $SRC_HASH ]] || err "Could not get source hash — run: nix build .#langfuse"
log "Source hash: $SRC_HASH"
set_hash 1 "$SRC_HASH"

# ── 3. pnpm major version ────────────────────────────────────────────────────
PNPM_FIELD=$(curl -fsSL \
  "https://raw.githubusercontent.com/langfuse/langfuse/v${LATEST}/package.json" |
  jq -r '.packageManager // ""')

if [[ $PNPM_FIELD =~ pnpm@([0-9]+)\. ]]; then
  NEW_MAJOR="${BASH_REMATCH[1]}"
  CURRENT_MAJOR=$(grep -oP 'pnpm_\K[0-9]+' "$PKG" | head -1)
  if [[ $NEW_MAJOR != "$CURRENT_MAJOR" ]]; then
    log "pnpm major changed: $CURRENT_MAJOR → $NEW_MAJOR"
    sed -i "s/pnpm_${CURRENT_MAJOR}/pnpm_${NEW_MAJOR}/g" "$PKG"
  fi
fi

# ── 4. Discover pnpm deps hash ───────────────────────────────────────────────
set_hash 2 "$FAKE"

log "Fetching pnpm deps hash (downloads all dependencies)..."
PNPM_HASH=$(extract_hash)
[[ -n $PNPM_HASH ]] || err "Could not get pnpm deps hash — run: nix build .#langfuse"
log "pnpm deps hash: $PNPM_HASH"
set_hash 2 "$PNPM_HASH"

# ── 5. Verify ────────────────────────────────────────────────────────────────
log "Verifying full build..."
git add "$PKG"
nix build ".#langfuse" 2>&1 | tail -3
log "Done. langfuse $LATEST ready."
