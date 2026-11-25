#!/usr/bin/env bash
# Collects public Buzz community invites (https://<name>.communities.buzz.xyz/invite/<code>)
# from GitHub code search, the files in sources.txt and the directory sites in sites.txt.
#
# Reads the previous state from STATE_IN (JSON, may be missing or empty) and writes:
#   $OUT/state.json   invites still posted or still valid, and every community seen so far
#   $OUT/report.md    the issue body (without the state block)
#   $OUT/new.md       communities seen for the first time and not in joined.txt
# Writes "new=true" to $GITHUB_OUTPUT when new.md has entries on a run with previous state.
#
# Invites live at most 30 days (buzz-app admin-protocol.ts), so an invite leaves the report
# 30 days after it was first seen, or at its expiry when the code carries one (v1 codes).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${OUT:-.}"
state_in="${STATE_IN:-}"
now="$(date -u +%s)"
max_age=$((30 * 86400))
link_re='https://[a-z0-9-]+\.communities\.buzz\.xyz/invite/[A-Za-z0-9._-]+'
# Docs and test fixtures, not real communities.
placeholder_re='^(acme|example|your-community|my-community|test|primary)$'
# An invite found only in test code is a fixture.
testpath_re='/(tests?|spec|__tests__|fixtures?|Tests)/|\.(test|spec)\.[a-z]+$'

found="$(mktemp)"
trap 'rm -f "$found"' EXIT

# Appends "<url>\t<source>" for every invite link in stdin.
collect() {
  grep -oE "$link_re" | sort -u | sed "s|\$|\t$1|" >>"$found" || true
}

fetch_file() { # owner/repo path
  gh api "repos/$1/contents/$2" --jq .content | base64 -d
}

# GitHub code search finds new places; it can lag behind, so known files are read directly too.
if items="$(gh api -X GET search/code -f q='"communities.buzz.xyz/invite"' -f per_page=100 \
  --jq '.items[] | "\(.repository.full_name) \(.path)"' 2>&1)"; then
  while read -r repo path; do
    [[ -z $repo ]] && continue
    fetch_file "$repo" "$path" | collect "https://github.com/$repo/blob/HEAD/$path" ||
      echo "warning: could not read $repo/$path" >&2
  done <<<"$items"
else
  echo "warning: code search failed: $items" >&2
fi

while read -r repo path; do
  [[ -z $repo || $repo == \#* ]] && continue
  fetch_file "$repo" "$path" | collect "https://github.com/$repo/blob/HEAD/$path" ||
    echo "warning: could not read $repo/$path" >&2
done <"$here/sources.txt"

while read -r site; do
  [[ -z $site || $site == \#* ]] && continue
  curl -fsSL -m 30 "$site" | collect "$site" || echo "warning: could not fetch $site" >&2
done <"$here/sites.txt"

joined="$({ grep -vE '^\s*(#|$)' "$here/joined.txt" || true; } | jq -R . | jq -s .)"
prev='{"invites": {}, "communities": []}'
if [[ -n $state_in && -s $state_in ]]; then
  prev="$(cat "$state_in")"
fi

# State: every invite still posted somewhere (expired ones too, so a stale invite that stays
# on a page never counts as new again), plus every community ever seen.
# v1 codes are base64url JSON with the expiry "e" before the first dot; v2 codes carry none.
jq -Rn --argjson prev "$prev" --argjson now "$now" --argjson max "$max_age" \
  --arg placeholder "$placeholder_re" --arg testpath "$testpath_re" '
  def b64url: gsub("-"; "+") | gsub("_"; "/") | . + ("=" * ((4 - length % 4) % 4)) | @base64d;
  ([inputs | split("\t") | {url: .[0], source: .[1]}]
   | group_by(.url)
   | map({
       url: .[0].url,
       community: (.[0].url | capture("^https://(?<c>[a-z0-9-]+)\\.").c),
       code: (.[0].url | sub("^.*/invite/"; "")),
       sources: (map(.source) | unique)
     })
   | map(select(((.community | test($placeholder)) | not) and ((.code | length) >= 20)))
   | map(select(any(.sources[]; test($testpath) | not)))
   | map(. as $i | ($prev.invites[$i.url] // {}) as $p
       | {key: $i.url, value: {
           community: $i.community,
           first_seen: ($p.first_seen // $now),
           expires: (if ($i.code | startswith("eyJ"))
                     then (try ($i.code | split(".")[0] | b64url | fromjson | .e) catch null)
                     else null end),
           sources: $i.sources
         }})
   | from_entries) as $found
  # An invite that left every source may still work until it expires.
  | ($prev.invites | with_entries(select(
      ($found[.key] == null) and ((.value.expires // (.value.first_seen + $max)) > $now)))) as $kept
  | {
      invites: ($kept + $found),
      communities: ($prev.communities + [$found[].community] | unique)
    }
' <"$found" >"$out/state.json"

# Report: valid invites only, newest per community, joined communities marked.
jq -r --argjson joined "$joined" --argjson now "$now" --argjson max "$max_age" '
  def day: strftime("%Y-%m-%d");
  .invites | to_entries | map(.value + {url: .key})
  | map(select((.expires // (.first_seen + $max)) > $now))
  | group_by(.community)
  | map(sort_by(-.first_seen))
  | sort_by(.[0].community)
  | (["Buzz community invites seen in public places. An invite is valid for at most 30 days; "
      + "\"~\" marks an upper bound counted from when it was first seen here, and a used-up or "
      + "revoked invite still shows. Joined communities are in `watch/buzz-invites/joined.txt`.", "",
      "| Community | Invite | First seen | Valid until | Found in |",
      "|---|---|---|---|---|"]
     + map(.[0] as $i
        | "| \($i.community)\(if ($joined | index($i.community)) then " (joined)" else "" end) "
          + "| [link](\($i.url)) | \($i.first_seen | day) "
          + "| \(if $i.expires then ($i.expires | day) else "~" + (($i.first_seen + $max) | day) end) "
          + "| \($i.sources | map("[\(sub("^https://(github.com/)?"; "") | sub("/blob/HEAD/"; "/") | .[0:60])](\(.))") | join(", ")) |"))
  | .[]
' "$out/state.json" >"$out/report.md"

# New: communities with a valid invite, never seen before and not joined.
jq -r --argjson prev "$prev" --argjson joined "$joined" --argjson now "$now" --argjson max "$max_age" '
  .invites | to_entries | map(.value + {url: .key})
  | map(select((.expires // (.first_seen + $max)) > $now))
  | map(select(.community as $c | ($prev.communities + $joined) | index($c) | not))
  | group_by(.community) | map(max_by(.first_seen))
  | .[] | "- \(.community): \(.url)"
' "$out/state.json" >"$out/new.md"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  # The first run has nothing to compare with; it only fills the issue.
  if [[ $(jq '.communities | length' <<<"$prev") -gt 0 && -s $out/new.md ]]; then
    echo "new=true" >>"$GITHUB_OUTPUT"
  else
    echo "new=false" >>"$GITHUB_OUTPUT"
  fi
fi
