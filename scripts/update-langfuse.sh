#!/usr/bin/env bash
# Update pkgs/langfuse/default.nix to the latest Langfuse release: version,
# source hash, pnpm major and pnpm deps hash, then a full build.
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
# The build is meant to fail; on any other failure, show why instead of
# leaving the caller with an empty hash.
extract_hash() {
  local out
  out=$(nix build ".#langfuse" 2>&1 || true)
  if ! grep -oP '(?<=got:    )sha256-\S+' <<<"$out" | head -1; then
    echo "$out" | tail -40 >&2
  fi
}

# pnpm version a release needs: engines.pnpm, or packageManager before
# Langfuse dropped it (v4.51.0).
required_pnpm() {
  curl -fsSL "https://raw.githubusercontent.com/langfuse/langfuse/v$1/package.json" |
    jq -r '.engines.pnpm // (.packageManager // "" | ltrimstr("pnpm@") | split("+")[0])'
}

# Version of pnpm_<major> in the flake's locked nixpkgs, empty if missing.
nixpkgs_pnpm() {
  nix eval --raw --inputs-from . "nixpkgs#pnpm_$1.version" 2>/dev/null || true
}

# ── 1. Newest release our nixpkgs' pnpm can install ───────────────────────
# Langfuse pins pnpm close to its newest release, and an older pnpm can't
# parse a newer pnpm-workspace.yaml, so wait for nixpkgs rather than fail.
RELEASES=$(curl -fsSL "https://api.github.com/repos/langfuse/langfuse/releases?per_page=30" |
  jq -r '.[] | select(.draft or .prerelease | not) | .tag_name | ltrimstr("v")' | sort -rV)
[[ -n $RELEASES ]] || err "Could not fetch releases"

LATEST=""
for v in $RELEASES; do
  want=$(required_pnpm "$v")
  [[ $want =~ ^([0-9]+)\. ]] || err "No pnpm version in v$v/package.json"
  major="${BASH_REMATCH[1]}"
  have=$(nixpkgs_pnpm "$major")
  if [[ -n $have && $(printf '%s\n' "$want" "$have" | sort -V | head -1) == "$want" ]]; then
    LATEST="$v"
    PNPM_MAJOR="$major"
    break
  fi
  log "Skipping $v: needs pnpm $want, nixpkgs has pnpm_$major ${have:-(none)}"
done
[[ -n $LATEST ]] || err "No recent release fits nixpkgs' pnpm"

CURRENT=$(grep -oP 'version = "\K[^"]+' "$PKG" | head -1)
if [[ $(printf '%s\n' "$CURRENT" "$LATEST" | sort -V | tail -1) == "$CURRENT" ]]; then
  log "Langfuse already at $CURRENT (newest usable: $LATEST) — nothing to do."
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
CURRENT_MAJOR=$(grep -oP 'pnpm_\K[0-9]+' "$PKG" | head -1)
if [[ $PNPM_MAJOR != "$CURRENT_MAJOR" ]]; then
  log "pnpm major changed: $CURRENT_MAJOR → $PNPM_MAJOR"
  sed -i "s/pnpm_${CURRENT_MAJOR}/pnpm_${PNPM_MAJOR}/g" "$PKG"
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
nix build ".#langfuse" 2>&1 | tail -40
log "Done. langfuse $LATEST ready."
