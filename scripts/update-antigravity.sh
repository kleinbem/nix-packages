#!/usr/bin/env bash
# Update pkgs/antigravity/versions.json to the latest Google Antigravity releases.
#
# Discovers the latest versions from Google's OFFICIAL Cloud Run updater
# endpoints, then pins each artifact by prefetching its hash directly from
# Google's CDNs (storage.googleapis.com / edgedl.me.gvt1.com). We deliberately
# do NOT depend on any third-party flake — this script is the whole supply
# chain, and every hash is computed from the real upstream download.
#
# Usage:  ./scripts/update-antigravity.sh
# Deps:   bash, curl, jq, nix (nix-prefetch-url, nix hash)
set -euo pipefail

cd "$(dirname "$0")/.."
OUTPUT_JSON="pkgs/antigravity/versions.json"

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

# Official Google update-discovery endpoints (Cloud Run).
APP_RELEASES="https://antigravity-auto-updater-974169037036.us-central1.run.app/releases"
IDE_RELEASES="https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases"
CLI_MANIFEST_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"

# CDN bases for the actual artifacts.
APP_BASE="https://storage.googleapis.com/antigravity-public/antigravity-hub"
IDE_BASE="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable"

[[ -f $OUTPUT_JSON ]] || echo "{}" >"$OUTPUT_JSON"

prefetch_sri() { # url [name] -> SRI sha256
  local url="$1" name="${2:-}" raw
  if [[ -n $name ]]; then
    raw=$(nix-prefetch-url --type sha256 --name "$name" "$url")
  else
    raw=$(nix-prefetch-url --type sha256 "$url")
  fi
  nix hash to-sri --type sha256 "$raw"
}

current_version() { # name -> version-from-url or "none"
  jq -r --arg n "$1" '.[$n]."x86_64-linux".url // "none"' "$OUTPUT_JSON" |
    grep -oP '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' || echo "none"
}

write_back() { # name <json-payload>
  local tmp
  tmp=$(mktemp)
  jq --arg n "$1" --argjson p "$2" '.[$n] = $p' "$OUTPUT_JSON" >"$tmp"
  mv "$tmp" "$OUTPUT_JSON"
}

# ── App (2.0) and IDE share the same versioned-tarball layout ───────────────
process_hub() { # display-name  version  base-url  filename(URL-encoded)  [name-arg]
  local name="$1" version="$2" base="$3" file="$4" name_arg="${5:-}"
  if [[ "$(current_version "$name")" == "$version" ]]; then
    log "$name already at $version — skipping."
    return 0
  fi
  log "Updating $name -> $version"
  local payload="{}"
  local plats=(
    "x86_64-linux:linux-x64"
    "aarch64-linux:linux-arm"
    "x86_64-darwin:darwin-x64"
    "aarch64-darwin:darwin-arm"
  )
  for p in "${plats[@]}"; do
    local nix_os="${p%%:*}" api_os="${p##*:}"
    local fname="$file"
    # .dmg for darwin, .tar.gz for linux
    [[ $nix_os == *darwin* ]] && fname="${file%.tar.gz}.dmg"
    local url="${base}/${version}/${api_os}/${fname}"
    log "  hash $nix_os ..."
    local hash
    hash=$(prefetch_sri "$url" "$name_arg")
    payload=$(jq --arg k "$nix_os" --arg u "$url" --arg h "$hash" \
      '.[$k]={url:$u,hash:$h}' <<<"$payload")
  done
  write_back "$name" "$payload"
}

log "Discovering latest versions ..."
APP_VER=$(curl -fsSL "$APP_RELEASES" | jq -r '.[0] | .version + "-" + .execution_id')
IDE_VER=$(curl -fsSL "$IDE_RELEASES" | jq -r '.[0] | .version + "-" + .execution_id')
[[ -n $APP_VER && $APP_VER != "null-null" ]] || {
  err "no app version"
  exit 1
}
[[ -n $IDE_VER && $IDE_VER != "null-null" ]] || {
  err "no IDE version"
  exit 1
}

process_hub "Antigravity 2.0" "$APP_VER" "$APP_BASE" "Antigravity.tar.gz" ""
process_hub "Antigravity IDE" "$IDE_VER" "$IDE_BASE" "Antigravity%20IDE.tar.gz" "Antigravity_IDE.tar.gz"

# ── CLI: manifest already carries url + sha512 per platform ─────────────────
log "Updating Antigravity CLI ..."
cli_payload="{}"
cli_plats=(
  "x86_64-linux:linux_amd64"
  "aarch64-linux:linux_arm64"
  "x86_64-darwin:darwin_amd64"
  "aarch64-darwin:darwin_arm64"
)
for p in "${cli_plats[@]}"; do
  nix_os="${p%%:*}" api_os="${p##*:}"
  manifest=$(curl -fsSL "${CLI_MANIFEST_BASE}/${api_os}.json") || {
    err "CLI manifest ${api_os}"
    exit 1
  }
  url=$(jq -r '.url' <<<"$manifest")
  sha=$(jq -r '.sha512' <<<"$manifest")
  cli_payload=$(jq --arg k "$nix_os" --arg u "$url" --arg h "sha512-$sha" \
    '.[$k]={url:$u,hash:$h}' <<<"$cli_payload")
done
write_back "Antigravity CLI" "$cli_payload"

log "Done. $OUTPUT_JSON is up to date."
