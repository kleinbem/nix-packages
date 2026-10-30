#!/usr/bin/env bash
# Prints a Markdown report of what happened on the watched upstream PRs and
# issues since
# SINCE (ISO 8601, default 8 days ago) and exits 0. PRS_FILE overrides the list;
# activity by the PR author and by IGNORE (space-separated logins) is skipped. Writes "changed=true" to
# $GITHUB_OUTPUT when something needs a look: a merge conflict, the PR merged
# or closed, new comments or reviews, or CI runs beyond the security checks.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
prs_file="${PRS_FILE:-$here/prs.txt}"
ignore="${IGNORE:-kleinbem github-actions coderabbitai}"
since="${SINCE:-$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)}"
# Checks that run on every outside PR without a maintainer's approval.
always='Security|Semgrep|zizmor|DCO|Reconcil|Stale|Previous Base'
changed=false

echo "| PR | State | What happened since ${since%%T*} |"
echo "|---|---|---|"
while read -r ref; do
  [[ -z $ref || $ref == \#* ]] && continue
  repo="${ref%%#*}" number="${ref##*#}"
  # gh issue view also answers for a PR, so fall back to it only when the
  # number is no PR at all; any other error (rate limit, bad repo) fails the run.
  # An issue has no merge state, reviews or checks; fill them in empty.
  if ! pr="$(gh pr view "$number" --repo "$repo" \
    --json url,title,author,state,mergeable,mergedAt,closedAt,comments,reviews,statusCheckRollup 2>&1)"; then
    if [[ $pr != *"Could not resolve to a PullRequest"* ]]; then
      echo "$ref: $pr" >&2
      exit 1
    fi
    pr="$(gh issue view "$number" --repo "$repo" --json url,title,author,state,closedAt,comments |
      jq '. + {mergeable: null, mergedAt: null, reviews: [], statusCheckRollup: []}')"
  fi
  notes="$(jq -r --arg since "$since" --arg always "$always" --arg ignore "$ignore" '
    ([.author.login] + ($ignore | split(" "))) as $skip
    | [ (if .state == "OPEN" and .mergeable == "CONFLICTING" then "merge conflict" else empty end),
        (if (.mergedAt // "") > $since then "merged" else empty end),
        (if .mergedAt == null and (.closedAt // "") > $since then "closed" else empty end),
        ([.comments[], .reviews[]
          | select(.author.login as $who | $skip | index($who) | not)
          | select((.createdAt // .submittedAt // "") > $since)
          | .author.login] | unique
          | if length > 0 then "new comments or reviews: " + join(", ") else empty end),
        ([.statusCheckRollup[]
          | select(((.name // .context) | test($always)) | not)
          | select((.completedAt // "") > $since)] | length
          | if . > 0 then "CI ran (\(.) checks)" else empty end)
      ] | join("; ")' <<<"$pr")"
  state="$(jq -r '.state' <<<"$pr")"
  line="$(jq -r '"[\(.title)](\(.url))"' <<<"$pr")"
  if [[ -n $notes ]]; then
    changed=true
  else
    notes="nothing new"
  fi
  echo "| $line | $state | $notes |"
done <"$prs_file"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  echo "changed=$changed" >>"$GITHUB_OUTPUT"
fi
