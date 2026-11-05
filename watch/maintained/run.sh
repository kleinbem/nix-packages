#!/usr/bin/env bash
# Prints a Markdown report on the nixpkgs packages and NixOS modules MAINTAINER
# (default kleinbem) maintains, read from nixpkgs itself so the list grows on
# its own: others' open PRs and issues naming them, review requests, failed
# Hydra builds and failed nixpkgs-update runs.
# Writes "changed=true" to $GITHUB_OUTPUT only when something is new since
# SINCE (ISO 8601, default 26 hours ago); old open items stay in the report.
set -euo pipefail

maintainer="${MAINTAINER:-kleinbem}"
since="${SINCE:-$(date -u -d '26 hours ago' +%Y-%m-%dT%H:%M:%SZ)}"
since_epoch="$(date -u -d "$since" +%s)"
systems='x86_64-linux aarch64-linux aarch64-darwin x86_64-darwin'
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
changed=false

# Packages: attrs whose meta.maintainers has MAINTAINER, versioned sets included
# (python313Packages.foo). The channel lags master by a few days.
curl -sfL --retry 3 https://channels.nixos.org/nixos-unstable/packages.json.br |
  brotli -dc |
  jq -r --arg m "$maintainer" '.packages | to_entries[]
    | select(any(.value.meta.maintainers[]?; .github == $m)) | .key' |
  sort -u >"$work/attrs"

# Modules: any file under nixos/modules that names MAINTAINER (meta.maintainers).
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/NixOS/nixpkgs "$work/nixpkgs"
git -C "$work/nixpkgs" sparse-checkout set nixos/modules
(git -C "$work/nixpkgs" grep -lw "$maintainer" -- nixos/modules || true) |
  sed -E 's|/default\.nix$||; s|.*/||; s|\.nix$||' | sort -u >"$work/modules"

if [[ ! -s $work/attrs && ! -s $work/modules ]]; then
  echo "No packages or modules list $maintainer as maintainer."
  exit 0
fi

# Title terms: the attr without its package set (python313Packages.foo → foo),
# and nixos/<module>.
{
  sed -E 's/^[A-Za-z0-9_]+Packages[0-9_]*\.//' "$work/attrs"
  sed 's|^|nixos/|' "$work/modules"
} | sort -u >"$work/terms"

echo "Packages: $(paste -sd' ' "$work/attrs" | sed 's/ /, /g')"
echo
echo "Modules: $(paste -sd' ' "$work/modules" | sed 's/ /, /g')"
echo

# --- PRs and issues -------------------------------------------------------------

fields=number,title,url,author,createdAt,updatedAt
# Most recently updated first, so a busy term's newest items aren't cut off
# by the limit. The search API allows 30 requests a minute; wait out a 403 once.
search() {
  local args=(--repo NixOS/nixpkgs --state open --sort updated --order desc --limit 100 --json "$fields")
  gh "$@" "${args[@]}" || { sleep 61 && gh "$@" "${args[@]}"; }
}
while read -r term; do
  search search issues --include-prs --match title "$term" |
    jq -c --arg term "$term" '.[]
      # A title search matches words anywhere; keep titles that name the
      # attr itself ("foo: 1 -> 2", "nixos/foo: …", "Build failure: foo").
      | select(.title | test("(^|[\\s/,(])\($term | gsub("(?<c>[.+])"; "\\\(.c)"))($|[\\s:,)])"))'
  sleep 2
done <"$work/terms" >"$work/items.json"
search search prs --review-requested "$maintainer" | jq -c '.[]' >>"$work/items.json"

jq -s --arg m "$maintainer" 'unique_by(.url) | map(select(.author.login != $m))' \
  "$work/items.json" >"$work/items"
if jq -e --arg since "$since" 'any(.[]; .updatedAt > $since)' "$work/items" >/dev/null; then
  changed=true
fi

echo "### Open PRs and issues"
echo
if jq -e 'length == 0' "$work/items" >/dev/null; then
  echo "None."
else
  echo "| | Item | Author | Opened | Updated |"
  echo "|---|---|---|---|---|"
  jq -r --arg since "$since" 'sort_by(.updatedAt) | reverse | .[]
    | "| \(if .createdAt > $since then "new" elif .updatedAt > $since then "updated" else "" end)"
      + " | \(if .url | test("/pull/") then "PR" else "issue" end) [\(.title | gsub("\\|"; "\\|"))](\(.url))"
      + " | \(.author.login) | \(.createdAt[:10]) | \(.updatedAt[:10]) |"' "$work/items"
fi
echo

# --- Hydra ------------------------------------------------------------------------

# Prints "<job>\t<build url>\t<stoptime>" for the latest finished build of a job
# that failed; nothing when it succeeded or the job doesn't exist.
hydra_failed() {
  local build
  build="$(curl -sL --retry 2 -m 30 -H 'Accept: application/json' \
    "https://hydra.nixos.org/job/$1/latest-finished" || true)"
  jq -r --arg job "$1" 'select(type == "object" and .buildstatus != null and .buildstatus != 0)
    | "\($job)\thttps://hydra.nixos.org/build/\(.id)\t\(.stoptime)"' <<<"$build" 2>/dev/null || true
}

{
  while read -r attr; do
    for system in $systems; do
      hydra_failed "nixpkgs/trunk/$attr.$system"
    done
  done <"$work/attrs"
  while read -r module; do
    for system in x86_64-linux aarch64-linux; do
      hydra_failed "nixos/trunk-combined/nixos.tests.$module.$system"
    done
  done <"$work/modules"
} >"$work/failed"

echo "### Failed Hydra builds"
echo
if [[ ! -s $work/failed ]]; then
  echo "None."
else
  while IFS=$'\t' read -r job url stoptime; do
    mark=""
    if ((stoptime > since_epoch)); then
      mark="new: "
      changed=true
    fi
    echo "- ${mark}[$job]($url), $(date -u -d "@$stoptime" +%F)"
  done <"$work/failed"
fi
echo

# --- nixpkgs-update ---------------------------------------------------------------

# The bot's newest log per attr; a line starting with "error:" means the update
# was found but didn't build or apply.
echo "### Failed nixpkgs-update runs"
echo
logs=https://nixpkgs-update-logs.nix-community.org
found=false
while read -r attr; do
  latest="$(curl -sL -m 30 "$logs/$attr/" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}\.log' | sort | tail -1 || true)"
  [[ -z $latest ]] && continue
  if curl -sL -m 30 "$logs/$attr/$latest" | grep '^error:' >/dev/null; then
    found=true
    mark=""
    if [[ ! ${latest%.log} < ${since%%T*} ]]; then
      mark="new: "
      changed=true
    fi
    echo "- ${mark}[$attr, ${latest%.log}]($logs/$attr/$latest)"
  fi
done <"$work/attrs"
$found || echo "None."

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  echo "changed=$changed" >>"$GITHUB_OUTPUT"
fi
