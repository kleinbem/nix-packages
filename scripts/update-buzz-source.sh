#!/usr/bin/env bash
# Update pkgs/buzz/source.json to the latest block/buzz commit.
#
# The 7 Buzz packages are crates of one workspace, so they share this one
# commit, source hash and Cargo vendor hash. All of them are built at the end,
# so a broken bump never reaches the auto-merged PR.
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
backup="$(mktemp)"
# Until the real cargoHash is written, any exit (an error, Ctrl-C) restores
# source.json: a left-over dummy hash at the new rev looks up to date next run.
restore() {
  cp "$backup" "$PKG_JSON"
  rm -f "$backup"
}
trap 'rm -f "$backup"' EXIT
cp "$PKG_JSON" "$backup"
trap restore EXIT
jq --arg v "$NEW_VERSION" \
  --arg r "$LATEST_REV" \
  --arg h "$SRC_HASH" \
  --arg c "$FAKE_HASH" \
  '.version = $v | .rev = $r | .hash = $h | .cargoHash = $c' \
  "$PKG_JSON" >"$PKG_JSON.tmp"
mv "$PKG_JSON.tmp" "$PKG_JSON"

GOT_CARGO_HASH=$( (nix build .#buzz-cli 2>&1 || true) | sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[A-Za-z0-9+/=]+).*/\1/p' | head -1)
[[ -n $GOT_CARGO_HASH ]] || err "Could not extract cargoHash from nix build"
log "Discovered cargoHash: $GOT_CARGO_HASH"

# ── 4. Save canonical hashes ──────────────────────────────────────────────────
jq --arg c "$GOT_CARGO_HASH" '.cargoHash = $c' "$PKG_JSON" >"$PKG_JSON.tmp"
mv "$PKG_JSON.tmp" "$PKG_JSON"
trap - EXIT
rm -f "$backup"

# ── 5. Verify builds ──────────────────────────────────────────────────────────
# All of them: they share the vendor hash, but each has its own patches,
# substitutions and test suite that a new upstream commit can break.
PACKAGES=(buzz-relay buzz-cli buzz-acp buzz-agent buzz-dev-mcp git-credential-nostr git-sign-nostr)
log "Verifying builds of ${PACKAGES[*]}..."
build_log="$(mktemp)"
if ! nix build --no-link --keep-going "${PACKAGES[@]/#/.#}" >"$build_log" 2>&1; then
  # nix only prints the last lines of a failed build; show each failed log.
  cat "$build_log" >&2
  grep -oE '/nix/store/[a-z0-9]{32}-[^ ]+\.drv' "$build_log" | sort -u | while read -r drv; do
    echo "::group::nix log $drv" >&2
    nix log "$drv" 2>&1 | tail -150 >&2 || true
    echo "::endgroup::" >&2
  done || true
  rm -f "$build_log"
  err "Build failed at ${LATEST_REV:0:9}"
fi
rm -f "$build_log"
log "Build verified! Buzz ecosystem bumped to $NEW_VERSION."
