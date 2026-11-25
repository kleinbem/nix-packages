#!/usr/bin/env bash
# Collects public Buzz community invites (https://<name>.communities.buzz.xyz/invite/<code>)
# from GitHub code search, the files in sources.txt, the directory sites in sites.txt, Nostr
# posts on the search relays in relays.txt (needs `nak`), Hacker News, and GitHub issues and PRs.
#
# Reads the previous state from STATE_IN (JSON, may be missing or empty) and writes:
#   $OUT/state.json   invites still posted or still valid, and every community seen so far
#   $OUT/report.md    the issue body (without the state block)
#   $OUT/new.md       communities seen for the first time and not in joined.txt
# Writes "new=true" to $GITHUB_OUTPUT when new.md has entries on a run with previous state.
#
# Invites live at most 30 days (buzz-app admin-protocol.ts). An invite leaves the report at
# the expiry its code carries (v1 codes), else 30 days after it was posted: the post's date on
# Nostr, Hacker News and GitHub issues, the commit that added the line (git blame) for files on
# GitHub, the first run that saw it otherwise.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${OUT:-.}"
state_in="${STATE_IN:-}"
now="$(date -u +%s)"
max_age=$((30 * 86400))
# The code may contain dots but never ends on one (a link at the end of a sentence).
link_re='https://[a-z0-9-]+\.communities\.buzz\.xyz/invite/[A-Za-z0-9._-]*[A-Za-z0-9_-]'
# Docs and test fixtures, not real communities.
placeholder_re='^(acme|example|your-community|my-community|test|primary)$'
# An invite found only in test code is a fixture.
testpath_re='/(tests?|spec|__tests__|fixtures?|Tests)/|\.(test|spec)\.[a-z]+$'

found="$(mktemp)"
trap 'rm -f "$found"' EXIT

# Appends "<url>\t<source>\t" for every invite link in stdin (no posting date).
collect() {
  { grep -oE "$link_re" || true; } | sort -u | awk -v src="$1" '{ print $0 "\t" src "\t" }' >>"$found"
}

# shellcheck disable=SC2016 # GraphQL variables, not shell ones
blame_query='query($owner: String!, $name: String!, $path: String!) {
  repository(owner: $owner, name: $name) { defaultBranchRef { target { ... on Commit {
    blame(path: $path) { ranges { startingLine endingLine commit { committedDate } } } } } } } }'

# Appends "<url>\t<source>\t<epoch>" for every invite link in a GitHub file, dated by the
# commit that last changed its line.
collect_github() { # owner/repo path
  local path src content blame
  path="$(jq -rn --arg p "$2" '$p | split("/") | map(@uri) | join("/")')"
  src="https://github.com/$1/blob/HEAD/$path"
  # Raw media type: the JSON form has no content for files over 1 MB.
  content="$(gh api -H 'Accept: application/vnd.github.raw+json' "repos/$1/contents/$path")" || return 1
  blame="$(gh api graphql -f query="$blame_query" -f owner="${1%%/*}" -f name="${1#*/}" -f path="$2" \
    --jq '[.data.repository.defaultBranchRef.target.blame.ranges[]
           | {s: .startingLine, e: .endingLine, d: (.commit.committedDate | fromdateiso8601)}]' 2>/dev/null)" ||
    blame='[]'
  { grep -noE "$link_re" <<<"$content" || true; } |
    jq -Rr --argjson blame "$blame" --arg src "$src" '
      capture("^(?<n>[0-9]+):(?<url>.*)$") | (.n | tonumber) as $n
      | "\(.url)\t\($src)\t\(first($blame[] | select(.s <= $n and $n <= .e) | .d) // "")"' >>"$found"
}

# GitHub code search finds new places; it can lag behind, so known files are read directly too.
if items="$(gh api -X GET search/code -f q='"communities.buzz.xyz/invite"' -f per_page=100 \
  --jq '.items[] | "\(.repository.full_name) \(.path)"' 2>&1)"; then
  while read -r repo path; do
    [[ -z $repo ]] && continue
    collect_github "$repo" "$path" || echo "warning: could not read $repo/$path" >&2
  done <<<"$items"
else
  echo "warning: code search failed: $items" >&2
fi

while read -r repo path; do
  [[ -z $repo || $repo == \#* ]] && continue
  collect_github "$repo" "$path" || echo "warning: could not read $repo/$path" >&2
done <"$here/sources.txt"

while read -r site; do
  [[ -z $site || $site == \#* ]] && continue
  curl -fsSL -m 30 "$site" | collect "$site" || echo "warning: could not fetch $site" >&2
done <"$here/sites.txt"

# Appends "<url>\t<source>\t<epoch>" for every invite link in JSON lines {text, source, date}.
collect_posts() {
  jq -r --arg re "$link_re" '(.text // "") as $t | .source as $s | (.date // "") as $d
    | [$t | scan($re)] | unique[] | "\(.)\t\($s)\t\($d)"' >>"$found"
}

# Nostr: Buzz is built on it, so most invites are shared there. Search relays (NIP-50) only.
if command -v nak >/dev/null; then
  while read -r relay; do
    [[ -z $relay || $relay == \#* ]] && continue
    # nak reads stdin, which here is relays.txt.
    timeout 60 nak req -k 1 --search 'communities.buzz.xyz/invite' -l 500 "$relay" </dev/null 2>/dev/null |
      jq -c '{text: .content, source: "https://njump.me/\(.id)", date: .created_at}' | collect_posts ||
      echo "warning: could not search $relay" >&2
  done <"$here/relays.txt"
else
  echo "warning: nak not found, Nostr skipped" >&2
fi

# Hacker News stories and comments (Algolia); the text is HTML-escaped.
curl -fsS -m 30 'https://hn.algolia.com/api/v1/search_by_date?query=communities.buzz.xyz&tags=(story,comment)&hitsPerPage=100' |
  jq -c '.hits[] | {text: ([.comment_text, .story_text, .url] | map(. // "") | join(" ")
                           | gsub("&#x2F;"; "/") | gsub("&amp;"; "&")),
                    source: "https://news.ycombinator.com/item?id=\(.objectID)", date: .created_at_i}' |
  collect_posts || echo "warning: could not search Hacker News" >&2

# GitHub issues and PRs, with their comments; code search doesn't cover them.
if hits="$(gh api -X GET search/issues -f per_page=100 -f sort=updated -f order=desc \
  -f q="\"communities.buzz.xyz/invite\" -repo:${GITHUB_REPOSITORY:-kleinbem/nix-packages}" \
  --jq '.items[] | {text: (.body // ""), source: .html_url, date: (.created_at | fromdateiso8601),
                     comments: .comments_url, count: .comments} | @json' 2>&1)"; then
  while read -r hit; do
    [[ -z $hit ]] && continue
    jq -c 'del(.comments, .count)' <<<"$hit" | collect_posts
    [[ $(jq -r .count <<<"$hit") == 0 ]] && continue
    gh api --paginate "$(jq -r .comments <<<"$hit")?per_page=100" \
      --jq '.[] | {text: (.body // ""), source: .html_url, date: (.created_at | fromdateiso8601)}' |
      collect_posts || echo "warning: could not read comments of $(jq -r .source <<<"$hit")" >&2
  done <<<"$hits"
else
  echo "warning: issue search failed: $hits" >&2
fi

joined="$({ grep -vE '^\s*(#|$)' "$here/joined.txt" || true; } | jq -R . | jq -s .)"
prev='{"invites": {}, "communities": []}'
has_prev=false
if [[ -n $state_in && -s $state_in ]]; then
  prev="$(cat "$state_in")"
  has_prev=true
fi

# State: every invite still posted somewhere (expired ones too, so a stale invite that stays
# on a page never counts as new again), plus every community that had a valid invite.
# v1 codes are base64url JSON with the expiry "e" before the first dot; v2 codes carry none.
jq -Rn --argjson prev "$prev" --argjson now "$now" --argjson max "$max_age" \
  --arg placeholder "$placeholder_re" --arg testpath "$testpath_re" '
  def b64url: gsub("-"; "+") | gsub("_"; "/") | . + ("=" * ((4 - length % 4) % 4)) | @base64d;
  def valid: (.expires // (.first_seen + $max)) > $now;
  ([inputs | split("\t") | {url: .[0], source: .[1], posted: (.[2] | if . == "" or . == null then null else tonumber end)}]
   | group_by(.url)
   | map({
       url: .[0].url,
       community: (.[0].url | capture("^https://(?<c>[a-z0-9-]+)\\.").c),
       code: (.[0].url | sub("^.*/invite/"; "")),
       sources: (map(.source) | unique),
       posted: ([.[].posted | select(. != null)] | min)
     })
   | map(select(((.community | test($placeholder)) | not) and ((.code | length) >= 20)))
   | map(select(any(.sources[]; test($testpath) | not)))
   | map(. as $i | ($prev.invites[$i.url] // {}) as $p
       | {key: $i.url, value: {
           community: $i.community,
           first_seen: ([$p.first_seen // $now, $i.posted // $now] | min),
           expires: (if ($i.code | startswith("eyJ"))
                     then ((try ($i.code | split(".")[0] | b64url | fromjson | .e | numbers) catch null) // null)
                     else null end),
           sources: $i.sources
         }})
   | from_entries) as $found
  # An invite that left every source may still work until it expires.
  | ($prev.invites | with_entries(select(
      ($found[.key] == null) and (.value | valid)))) as $kept
  | {
      invites: ($kept + $found),
      communities: ($prev.communities + [$found[] | select(valid) | .community] | unique)
    }
' <"$found" >"$out/state.json"

# Report: valid invites only, newest per community, joined communities marked.
jq -r --argjson joined "$joined" --argjson now "$now" --argjson max "$max_age" '
  def day: strftime("%Y-%m-%d");
  # Paths come from any public repo: keep them from breaking the table or the link.
  def srclabel: sub("^https://(github.com/)?"; "") | sub("/blob/HEAD/"; "/") | .[0:60]
    | gsub("(?<c>[|\\[\\]\\\\])"; "\\\(.c)");
  .invites | to_entries | map(.value + {url: .key})
  | map(select((.expires // (.first_seen + $max)) > $now))
  | group_by(.community)
  | map(sort_by(-.first_seen))
  | sort_by(.[0].community)
  | (["Buzz community invites seen in public places. An invite is valid for at most 30 days; "
      + "\"~\" marks an upper bound counted from when it was posted (the commit that added it on "
      + "GitHub, else the first run that saw it), and a used-up or revoked invite still shows. Joined communities are in `watch/buzz-invites/joined.txt`.", "",
      "| Community | Invite | Posted | Valid until | Found in |",
      "|---|---|---|---|---|"]
     + map(.[0] as $i
        | "| \($i.community)\(if ($joined | index($i.community)) then " (joined)" else "" end) "
          + "| [link](\($i.url)) | \($i.first_seen | day) "
          + "| \(if $i.expires then ($i.expires | day) else "~" + (($i.first_seen + $max) | day) end) "
          + "| \($i.sources | map("[\(srclabel)](\(gsub("\\("; "%28") | gsub("\\)"; "%29") | gsub("\\|"; "%7C")))") | join(", ")) |"))
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
  if [[ $has_prev == true && -s $out/new.md ]]; then
    echo "new=true" >>"$GITHUB_OUTPUT"
  else
    echo "new=false" >>"$GITHUB_OUTPUT"
  fi
fi
