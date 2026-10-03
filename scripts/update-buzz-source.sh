#!/usr/bin/env bash
# Update pkgs/buzz/source.json to the latest block/buzz commit.
#
# Because all 7 Rust packages (buzz-relay, buzz-cli, buzz-acp, buzz-agent,
# buzz-dev-mcp, git-credential-nostr, git-sign-nostr) are crates in the same
# monorepo workspace, they share the exact same source commit, SRI source hash,
# and workspace Cargo vendor hash.
#
# This script:
#   1. Queries the GitHub API for the latest commit on block/buzz main.
#   2. Prefetches the source tarball and computes the SRI hash.
#   3. Temporarily sets a dummy cargoHash to discover the new vendor hash.
#   4. Updates pkgs/buzz/source.json atomically (updating all 7 packages).
#   5. Verifies builds of representative packages (buzz-cli, git-sign-nostr).
#
# Usage:  ./scripts/update-buzz-source.sh
# Deps:   bash, curl, jq, nix (nix-prefetch-url, nix hash)
set -euo pipefail

cd "$(dirname "$0")/.."
PKG_JSON="pkgs/buzz/source.json"
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# ── 1. Fetch latest upstream commit ──────────────────────────────────────────
log "Querying GitHub API for latest block/buzz commit..."
LATEST_COMMIT_DATA=$(curl -fsSL "https://api.github.com/repos/block/buzz/commits/main") || err "Could not reach GitHub API"
LATEST_REV=$(jq -r '.sha' <<<"$LATEST_COMMIT_DATA")
LATEST_DATE=$(jq -r '.commit.committer.date' <<<"$LATEST_COMMIT_DATA" | cut -d'T' -f1)
NEW_VERSION="0.1.0-unstable-${LATEST_DATE}"

CURRENT_REV=$(jq -r '.rev' "$PKG_JSON")
if [[ $CURRENT_REV == "$LATEST_REV" ]]; then
  log "Buzz source already at $LATEST_REV ($NEW_VERSION) — nothing to do."
  exit 0
fi

log "Updating Buzz source: ${CURRENT_REV:0:9} → ${LATEST_REV:0:9} ($NEW_VERSION)"

# ── 2. Prefetch source archive ────────────────────────────────────────────────
TARBALL_URL="https://github.com/block/buzz/archive/${LATEST_REV}.tar.gz"
log "Prefetching $TARBALL_URL ..."
RAW_SRC_HASH=$(nix-prefetch-url --unpack "$TARBALL_URL") || err "Could not prefetch $TARBALL_URL"
SRC_HASH=$(nix hash convert --hash-algo sha256 "$RAW_SRC_HASH")
log "Source SRI hash: $SRC_HASH"

# ── 3. Discover cargo vendor hash ─────────────────────────────────────────────
log "Setting dummy cargoHash to extract vendor hash from compiler..."
jq --arg v "$NEW_VERSION" \
  --arg r "$LATEST_REV" \
  --arg h "$SRC_HASH" \
  --arg c "$FAKE_HASH" \
  '.version = $v | .rev = $r | .hash = $h | .cargoHash = $c' \
  "$PKG_JSON" >"$PKG_JSON.tmp" && mv "$PKG_JSON.tmp" "$PKG_JSON"

git add "$PKG_JSON"

GOT_CARGO_HASH=$( (nix build .#buzz-cli 2>&1 || true) | grep -oP '(?<=got:    )sha256-\S+' | head -1)
if [[ -z $GOT_CARGO_HASH ]]; then
  # Revert dirty state before exiting
  git checkout -- "$PKG_JSON"
  err "Could not extract cargoHash from nix build"
fi
log "Discovered cargoHash: $GOT_CARGO_HASH"

# ── 4. Save canonical hashes ──────────────────────────────────────────────────
jq --arg c "$GOT_CARGO_HASH" '.cargoHash = $c' "$PKG_JSON" >"$PKG_JSON.tmp" && mv "$PKG_JSON.tmp" "$PKG_JSON"
git add "$PKG_JSON"

# ── 5. Verify builds ──────────────────────────────────────────────────────────
log "Verifying build of buzz-cli, git-sign-nostr, and buzz-dev-mcp..."
nix build .#buzz-cli .#git-sign-nostr .#buzz-dev-mcp 2>&1 | tail -3
log "Build verified! Buzz ecosystem bumped to $NEW_VERSION."
