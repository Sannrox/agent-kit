#!/usr/bin/env bash
# Inspect, claim, release, publish, or land the delivery lane of one GitHub
# Issue, or report the repository's lane capacity.
#
# A lane claim lives on GitHub so agents on different machines see it:
#   1. the branch <type>/<issue>, created from the default branch with an
#      atomic ref creation (POST /git/refs fails when the ref exists, so the
#      first claimant wins and every other claimant sees "claimed");
#   2. the authenticated login assigned to the Issue, visible in the Issue
#      list and timestamped by the Issue timeline;
#   3. an Issue comment naming the claiming agent ($LANE_AGENT) and the
#      SHA-256 of a random lane token. Only the claimant receives the token.
# Open Pull Requests that reference the Issue and any branch matching
# */<issue> or */<issue>-* count as claims too.
#
# Several agents may share one GitHub login, so the login never proves
# ownership. A claim is yours ("mine") only when $LANE_TOKEN hashes to the
# token on the Issue; everything else is another lane's claim. release, push,
# and land act only on your own lane unless --yes records the maintainer's
# approval.
#
# capacity counts live lanes repository-wide against the lane limit
# (ISSUE_LANE_LIMIT, default 3): open Pull Requests from claim branches plus
# claim branches without one whose Issue is open. A claim branch whose Issue is
# closed or whose Pull Request merged is stale: reported, never counted. claim
# refuses when no capacity remains, and deletes its new branch again if a
# concurrent claim pushed the repository over the limit.
#
# push publishes the lane branch with GitHub-verified commits through this
# kit's gh-verified-push.sh and resets the checkout to the published commit, so
# local HEAD equals the Pull Request head afterwards. It refuses a checkout
# merged with the default branch, and one rebased onto it after the publish
# unless --rebased is given. push --rebased publishes the rebased lane in two
# steps: it publishes the delta from the new base (the merge base of HEAD and
# the default branch) to HEAD as one verified commit on the scratch branch
# lane-publish/<issue>/rebase, then moves the claim branch onto that commit
# with one ref update guarded by the old tip, and deletes the scratch branch.
# It moves the claim branch only from a tip this checkout itself held (found
# in its reflog), so a stale checkout never overwrites newer published work,
# and the Pull Request head never points at a commit the default branch
# already holds. A crash before the move leaves the claim branch untouched
# (run push --rebased again); a crash after it is adopted by the next push.
#
# land withdraws any queued auto-merge, watches the Pull Request until its
# checks settle, then squash-merges it through the REST merge endpoint with the
# reviewed head (local HEAD unless --head is given) as the precondition, so
# GitHub refuses the merge if the head moved. It never queues auto-merge or a
# merge queue entry: a queued request survives later pushes, so it could land
# a head nobody reviewed. If land stops, nothing merges; run it again. An
# uncertain merge response is reconciled from the Pull Request state, never
# retried blindly. Success requires the merge on the default branch and the
# Issue closed; only then is the claim branch deleted.
#
# Usage:
#   bash issue-lane.sh capacity [--json]
#   bash issue-lane.sh capacity --self-test
#   bash issue-lane.sh check <issue> [--json]
#   LANE_AGENT=<name> bash issue-lane.sh claim <issue> [--dry-run]
#   bash issue-lane.sh release <issue> [--yes]
#   bash issue-lane.sh push <issue> [--rebased] [--yes]
#   bash issue-lane.sh land <issue> --pr <number> [--head <sha>] [--timeout-min <n>]
#       [--accept-failed <check>]... [--yes]
# Pass LANE_TOKEN=<token printed by claim> to check, release, push, and land.
#
# Exit codes: 0 unclaimed, mine, done, capacity left, or merged and confirmed;
# 3 claimed by another lane, not your lane (push, land), or no lane capacity
# left; 4 head moved (review and
# land the new head); 5 merge blocked (failed check, conflict, or behind main);
# 6 not mergeable yet when the watch timed out (land again to keep watching);
# 7 merged but a postcondition is unconfirmed (land again to recheck); 1 error.
# Requires an authenticated gh, git, and jq (--self-test needs only jq). Run
# inside the repository.
# ISSUE_LANE_POLL_SECONDS (default 60) sets how often land polls.
set -euo pipefail

# Canonical source: Sannrox/agent-kit skills/deliver-ready-issue. Derived from Sannrox/shikigami@331897846885e4a55697b0f1006d03b4f2a7495e.

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
STALE_HOURS=6
LANE_LIMIT="${ISSUE_LANE_LIMIT:-3}"
POLL_SECONDS="${ISSUE_LANE_POLL_SECONDS:-60}"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit "${1:-2}"
}

fail() {
  printf 'issue-lane: %s\n' "$1" >&2
  exit 1
}

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing required command: $tool"
  done
}

command_name="${1:-}"
case "$command_name" in
  capacity | check | claim | release | push | land) ;;
  -h | --help | "") usage 0 ;;
  *) usage ;;
esac
shift
issue=""
if [ "$command_name" != capacity ]; then
  issue="${1:-}"
  printf '%s' "$issue" | grep -Eq '^[0-9]+$' || fail "Issue number required, got '${issue}'"
  shift
fi

json_output=false
dry_run=false
confirm=false
self_test=false
rebased=false
land_pr=""
land_head=""
timeout_min=45
accepted_failures='[]'
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) json_output=true ;;
    --dry-run) dry_run=true ;;
    --yes) confirm=true ;;
    --self-test) self_test=true ;;
    --rebased) rebased=true ;;
    --pr | --head | --timeout-min | --accept-failed)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --pr) land_pr="$2" ;;
        --head) land_head="$2" ;;
        --timeout-min) timeout_min="$2" ;;
        --accept-failed) accepted_failures="$(jq -c --arg c "$2" '. + [$c]' <<< "$accepted_failures")" ;;
      esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done

case "$command_name" in
  push | land)
    [ "$json_output" = false ] && [ "$dry_run" = false ] \
      || fail "${command_name} does not take --json or --dry-run"
    ;;
  capacity)
    [ "$dry_run" = false ] && [ "$confirm" = false ] || fail "capacity does not take --dry-run or --yes"
    ;;
esac
[ "$command_name" = land ] || { [ -z "$land_pr$land_head" ] && [ "$accepted_failures" = '[]' ]; } \
  || fail "--pr, --head, and --accept-failed belong to land"
[ "$command_name" = capacity ] || [ "$self_test" = false ] || fail "--self-test belongs to capacity"
[ "$command_name" = push ] || [ "$rebased" = false ] || fail "--rebased belongs to push"
printf '%s' "$LANE_LIMIT" | grep -Eq '^[1-9][0-9]*$' || fail "ISSUE_LANE_LIMIT must be a positive whole number"
lane_agent="${LANE_AGENT:-}"
lane_token="${LANE_TOKEN:-}"
[ "$command_name" != claim ] || printf '%s' "$lane_agent" | grep -Eq '^[a-z0-9][a-z0-9-]{0,31}$' \
  || fail "set LANE_AGENT to a short lowercase agent name (for example claude or codex)"

# Claim branches are <type>/<issue> or <type>/<issue>-<slug>.
CLAIM_BRANCH_RE='^[^/]+/[0-9]+(-[^/]*)?$'

# Lane capacity from four JSON listings read on stdin, in order: branches
# ({name, sha}), open Pull Requests ({number, headRefName, closes}: closes
# counts the Issues it closes), open Issues ({number}), and merged Pull Request
# heads ({headRefName, sha}). They come through stdin, not arguments, because
# a long history outgrows the argument size limit. An open Pull Request is an
# implementation lane when its head is a claim branch or it closes an Issue. A
# merged head only makes a branch stale while the branch still points at it; a
# recreated branch is a new claim.
capacity_from_json() {
  jq -s --argjson limit "$LANE_LIMIT" --arg re "$CLAIM_BRANCH_RE" '
    def issue_of: capture("^[^/]+/(?<n>[0-9]+)") | .n | tonumber;
    . as [$branches, $prs, $open_issues, $merged]
    | [$prs[] | select((.headRefName | test($re)) or .closes > 0) | {number, headRefName}] as $lane_prs
    | [$prs[].headRefName] as $pr_heads
    | [$open_issues[].number] as $open
    | [$branches[] | select((.name | test($re)) and (.name as $n | $pr_heads | index($n) | not))] as $bare
    | [$bare[] | select(. as $b | any($merged[]; .headRefName == $b.name and .sha == $b.sha)
        or ($open | index($b.name | issue_of) | not)) | .name] as $stale
    | [$bare[] | .name | select(. as $n | $stale | index($n) | not)] as $orphans
    | ($lane_prs | length) + ($orphans | length) as $used
    | {limit: $limit, used: $used, remaining: ([$limit - $used, 0] | max),
       implementation_prs: $lane_prs, orphan_claim_branches: $orphans, stale_claim_branches: $stale}'
}

# Fetch the four listings from GitHub. Returns non-zero when any listing fails,
# so a partial view never passes for spare capacity.
live_capacity_json() {
  {
    gh api "repos/${repo}/git/matching-refs/heads/" --paginate \
      | jq -sc '[.[][] | {name: (.ref | ltrimstr("refs/heads/")), sha: .object.sha}]' || exit 1
    gh pr list -R "$repo" --state open --limit 1000 --json number,headRefName,closingIssuesReferences \
      --jq '[.[] | {number, headRefName, closes: (.closingIssuesReferences | length)}]' || exit 1
    gh api "repos/${repo}/issues?state=open&per_page=100" --paginate \
      | jq -sc '[.[][] | select(.pull_request == null) | {number}]' || exit 1
    gh api "repos/${repo}/pulls?state=closed&per_page=100" --paginate \
      | jq -sc '[.[][] | select(.merged_at != null) | {headRefName: .head.ref, sha: .head.sha}]' || exit 1
  } | capacity_from_json
}

print_capacity() {
  if [ "$json_output" = true ]; then
    printf '%s\n' "$1" | jq .
    return
  fi
  printf '%s\n' "$1" | jq -r '
    def list(f): if length == 0 then "none" else map(f) | join(", ") end;
    "lane capacity: \(.used)/\(.limit) used, \(.remaining) remaining",
    "implementation PRs: \(.implementation_prs | list("#\(.number) \(.headRefName)"))",
    "orphan claim branches: \(.orphan_claim_branches | list(.))",
    "stale claim branches: \(.stale_claim_branches | list(.))"'
}

# Offline checks of the counting rules in capacity_from_json.
capacity_self_test() {
  local report
  expect() { # description jq-filter branches prs open-issues merged
    report="$(printf '%s\n' "$3" "$4" "$5" "$6" | capacity_from_json)"
    printf '%s' "$report" | jq -e "$2" >/dev/null || fail "capacity self-test: $1: $report"
  }
  expect "empty repository" '.used == 0 and .remaining == 3' '[]' '[]' '[]' '[]'
  expect "orphan claim counts; other branches do not" \
    '.used == 1 and .orphan_claim_branches == ["feat/1"]' \
    '[{"name":"main","sha":"a"},{"name":"feat/1","sha":"a"},{"name":"docs/note","sha":"a"}]' '[]' '[{"number":1}]' '[]'
  expect "closed Issue makes its branch stale" '.used == 0 and .stale_claim_branches == ["feat/1"]' \
    '[{"name":"feat/1","sha":"a"}]' '[]' '[]' '[]'
  expect "a Pull Request and its branch are one lane" '.used == 1 and .orphan_claim_branches == []' \
    '[{"name":"feat/1","sha":"a"}]' '[{"number":10,"headRefName":"feat/1","closes":0}]' '[{"number":1}]' '[]'
  expect "slug branches count; Pull Requests closing no Issue do not" '.used == 1' \
    '[{"name":"codex/12-slug","sha":"a"}]' '[{"number":9,"headRefName":"deps/update","closes":0}]' '[{"number":12}]' '[]'
  expect "a Pull Request closing an Issue counts whatever its branch" \
    '.used == 1 and .implementation_prs == [{"number":9,"headRefName":"fix-timeout"}]' \
    '[]' '[{"number":9,"headRefName":"fix-timeout","closes":1}]' '[]' '[]'
  expect "over the limit clamps remaining at 0" '.used == 4 and .remaining == 0' '[]' \
    '[{"number":1,"headRefName":"feat/1"},{"number":2,"headRefName":"fix/2"},{"number":3,"headRefName":"docs/3"},{"number":4,"headRefName":"chore/4"}]' \
    '[]' '[]'
  expect "branch still at its merged head is stale" '.used == 0 and .stale_claim_branches == ["feat/1"]' \
    '[{"name":"feat/1","sha":"a"}]' '[]' '[{"number":1}]' '[{"headRefName":"feat/1","sha":"a"}]'
  expect "recreated branch past a merged head is live" '.used == 1 and .orphan_claim_branches == ["feat/1"]' \
    '[{"name":"feat/1","sha":"b"}]' '[]' '[{"number":1}]' '[{"headRefName":"feat/1","sha":"a"}]'
  printf 'issue-lane capacity self-test passed\n'
}

if [ "$self_test" = true ]; then
  require_tools jq
  LANE_LIMIT=3
  capacity_self_test
  exit 0
fi
require_tools gh git jq

repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"

if [ "$command_name" = capacity ]; then
  report="$(live_capacity_json)" || fail "cannot load the listings for lane capacity"
  print_capacity "$report"
  [ "$(printf '%s' "$report" | jq .remaining)" -gt 0 ] || exit 3
  exit 0
fi

login="$(gh api user --jq .login)"

fetch_issue() {
  gh issue view "$issue" --json number,title,state,labels,assignees,closedByPullRequestsReferences
}
issue_json="$(fetch_issue)"
issue_state="$(printf '%s' "$issue_json" | jq -r .state)"
issue_title="$(printf '%s' "$issue_json" | jq -r .title)"

# Derive the lane type deterministically so every machine computes the same
# branch: Conventional Commit type in the title (bug -> fix), then the type
# label (type:bug or bug -> fix, type:feature or enhancement -> feat, type:docs
# or documentation -> docs, type:refactor -> refactor, type:research ->
# research, in that order), then chore.
lane_type() {
  local from_title
  from_title="$(printf '%s' "$issue_title" | sed -nE 's/^([a-z]+)(\([^)]*\))?!?:.*/\1/p')"
  case "$from_title" in
    bug) printf 'fix' ; return ;;
    "") ;;
    *) printf '%s' "$from_title" ; return ;;
  esac
  printf '%s' "$issue_json" | jq -j '[.labels[].name] as $labels
    | first([["type:bug", "bug"], "fix"], [["type:feature", "enhancement"], "feat"],
        [["type:docs", "documentation"], "docs"], [["type:refactor"], "refactor"], [["type:research"], "research"]
        | select(any(.[0][]; IN($labels[]))) | .[1]) // "chore"'
}
lane_branch="$(lane_type)/${issue}"

sha256_short() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16
}

# Hours since an ISO-8601 UTC timestamp.
hours_since() {
  local then_epoch
  then_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s)"
  printf '%s' $(( ($(date -u +%s) - then_epoch) / 3600 ))
}

# The oldest claim marker comment: {id, created_at, agent, token_hash, count} or null.
# A live claim has exactly one marker (claim posts it, release removes it), so
# the oldest one wins and a later comment cannot replace the owner. Markers
# count only when their author can push (claimants create the branch) and
# when they postdate the last reopen (a landed lane leaves its marker behind;
# a lane whose Issue was reopened needs the maintainer to release or re-claim).
# Called as `x="$(claim_marker_json)" || ...`, where errexit is off: every
# fetch returns explicitly so an API failure never reads as "no owner".
claim_marker_json() {
  local reopened markers author can_push
  reopened="$(gh api "repos/${repo}/issues/${issue}/timeline" --paginate \
    | jq -rs '[.[] | .[]? // empty] | map(select(.event == "reopened")) | sort_by(.created_at) | last | .created_at // ""')" || return 1
  markers="$(gh api "repos/${repo}/issues/${issue}/comments" --paginate \
    | jq -sc --arg after "$reopened" '[.[][] | select((.body | test("<!-- issue-lane-claim ")) and .created_at > $after)]')" || return 1
  for author in $(printf '%s' "$markers" | jq -r '[.[].user.login] | unique | .[]'); do
    can_push="$(gh api "repos/${repo}/collaborators/${author}/permission" --jq .user.permissions.push)" || return 1
    if [ "$can_push" != true ]; then
      markers="$(printf '%s' "$markers" | jq -c --arg a "$author" 'map(select(.user.login != $a))')"
    fi
  done
  printf '%s' "$markers" \
    | jq -c '[.[] | {id, created_at,
           agent: (.body | capture("agent=(?<v>[a-z0-9-]+)").v),
           token_hash: (.body | capture("token-sha256=(?<v>[0-9a-f]+)").v)}]
        | if length == 0 then null else (sort_by(.created_at, .id) | first) + {count: length} end'
}

# True when $LANE_TOKEN hashes to the token of owner marker $1.
token_matches() {
  [ -n "$lane_token" ] && printf '%s' "$1" \
    | jq -e --arg h "$(printf '%s' "$lane_token" | sha256_short)" '.token_hash == $h' >/dev/null
}

# push and land act as the lane's owner: refuse (exit 3) unless LANE_TOKEN
# matches the owner marker, or --yes records the maintainer's approval.
require_mine() {
  local marker
  [ "$confirm" = false ] || return 0
  marker="$(claim_marker_json)" || fail "could not read the lane owner of #${issue}; refusing to ${command_name}"
  token_matches "$marker" && return 0
  printf 'issue-lane: #%s is not your lane (owner: %s); pass LANE_TOKEN from your claim, or --yes with the maintainer'"'"'s approval\n' \
    "$issue" "$(printf '%s' "$marker" | jq -r '.agent // "unknown"')" >&2
  exit 3
}

# Hours since the claim branch last moved, or since the claim marker, whichever is newer.
idle_hours() {
  local marker="$1" newest="" branch_at
  newest="$(printf '%s' "$marker" | jq -r '.created_at // empty')"
  if branch_at="$(gh api "repos/${repo}/commits/${lane_branch}" --jq .commit.committer.date 2>/dev/null)" \
    && [ -n "$branch_at" ] && { [ -z "$newest" ] || [[ "$branch_at" > "$newest" ]]; }; then
    newest="$branch_at"
  fi
  if [ -n "$newest" ]; then hours_since "$newest"; else printf 'null'; fi
}

# Every branch named <anything>/<issue> or <anything>/<issue>-<slug>.
claim_branches_json() {
  gh api "repos/${repo}/git/matching-refs/heads/" --paginate \
    | jq -sc --arg issue "$issue" '
        [.[][] | .ref | ltrimstr("refs/heads/")
          | select(test("^[^/]+/" + $issue + "(-[^/]*)?$"))]'
}

# Open Pull Requests that GitHub links to the Issue or whose head is a claim branch.
open_prs_json() {
  local numbers branches
  numbers="$(printf '%s' "$issue_json" | jq -r '.closedByPullRequestsReferences[].number')"
  branches="$(printf '%s' "$1" | jq -r '.[]')"
  {
    for number in $numbers; do
      gh pr view "$number" --json number,state,isDraft,headRefName,updatedAt,url,author \
        | jq -c 'select(.state == "OPEN")'
    done
    for branch in $branches; do
      gh pr list --state open --head "$branch" --json number,state,isDraft,headRefName,updatedAt,url,author \
        | jq -c '.[]'
    done
  } | jq -sc 'unique_by(.number) | sort_by(.number)'
}

# Assignees plus the age of the latest assignment event in hours.
assignment_json() {
  local last_assigned age_hours
  last_assigned="$(gh api "repos/${repo}/issues/${issue}/timeline" --paginate \
    | jq -rs '[.[] | .[]? // empty] | map(select(.event == "assigned")) | sort_by(.created_at) | last | .created_at // empty')"
  age_hours=null
  if [ -n "$last_assigned" ]; then
    age_hours="$(hours_since "$last_assigned")"
  fi
  printf '%s' "$issue_json" | jq -c --arg at "${last_assigned:-}" --argjson age "$age_hours" \
    '{assignees: [.assignees[].login], last_assigned_at: (if $at == "" then null else $at end), age_hours: $age}'
}

report_json() {
  local branches prs assignment marker owner mine idle verdict hint
  branches="$(claim_branches_json)"
  prs="$(open_prs_json "$branches")"
  assignment="$(assignment_json)"
  marker="$(claim_marker_json)" || fail "could not read the lane owner of #${issue}; refusing to judge the claim"
  mine=false
  if token_matches "$marker"; then mine=true; fi
  verdict=unclaimed
  hint=""
  if [ "$issue_state" != "OPEN" ]; then
    verdict=closed
  elif [ "$(printf '%s' "$prs" | jq length)" -gt 0 ] || [ "$(printf '%s' "$branches" | jq length)" -gt 0 ] \
    || [ "$marker" != null ]; then
    # An owner marker without a branch is an unfinished release: still a claim.
    verdict=claimed
  elif [ "$(printf '%s' "$assignment" | jq '.assignees | length')" -gt 0 ]; then
    if [ "$(printf '%s' "$assignment" | jq '.age_hours // 0')" -lt "$STALE_HOURS" ]; then
      verdict=claimed
    else
      hint="assignment older than ${STALE_HOURS}h without a branch or Pull Request; ask the maintainer before claiming"
    fi
  fi
  idle=null
  if [ "$verdict" = claimed ]; then
    if [ "$mine" = true ]; then
      verdict=mine
    else
      idle="$(idle_hours "$marker")"
      if [ "$(printf '%s' "$marker" | jq '.count // 0')" -gt 1 ]; then
        hint="several lane owner markers on the Issue; the oldest counts; ask the maintainer to clean up"
      elif [ "$marker" = null ]; then
        hint="claim carries no lane token (made by hand or before tokens); the same login does not make it yours; ask the maintainer before taking over"
      elif [ "$idle" != null ] && [ "$idle" -ge "$STALE_HOURS" ]; then
        hint="no activity for ${idle}h; possibly stale; ask the maintainer before taking over"
      fi
    fi
  fi
  owner="$(printf '%s' "$marker" | jq -c 'if . == null then null else {agent, claimed_at: .created_at, marker_id: .id} end')"
  jq -n \
    --arg repo "$repo" --argjson issue "$issue" --arg title "$issue_title" --arg state "$issue_state" \
    --arg lane_branch "$lane_branch" --argjson branches "$branches" --argjson prs "$prs" \
    --argjson assignment "$assignment" --argjson owner "$owner" --argjson idle "$idle" --argjson mine "$mine" \
    --arg verdict "$verdict" --arg hint "$hint" \
    '{repo: $repo, issue: $issue, title: $title, state: $state, lane_branch: $lane_branch,
      claim_branches: $branches, open_prs: $prs, assignment: $assignment,
      owner: $owner, mine: $mine, idle_hours: $idle,
      verdict: $verdict, hint: (if $hint == "" then null else $hint end)}'
}

print_report() {
  local report="$1"
  if [ "$json_output" = true ]; then
    printf '%s\n' "$report" | jq .
    return
  fi
  printf '%s\n' "$report" | jq -r '
    "Issue #\(.issue) [\(.state)] \(.title)",
    "lane branch: \(.lane_branch)",
    "claim branches: \(if (.claim_branches | length) == 0 then "none" else (.claim_branches | join(", ")) end)",
    "open PRs: \(if (.open_prs | length) == 0 then "none" else ([.open_prs[] | "#\(.number) \(if .isDraft then "draft" else "ready" end) \(.headRefName) by \(.author.login) updated \(.updatedAt)"] | join("; ")) end)",
    "assignees: \(if (.assignment.assignees | length) == 0 then "none" else (.assignment.assignees | join(", ")) + " (assigned \(.assignment.last_assigned_at // "unknown"), \(.assignment.age_hours // "?")h ago)" end)",
    "lane owner: \(if .owner then "\(.owner.agent) (claimed \(.owner.claimed_at))" else "unknown" end)\(if .idle_hours != null then ", idle \(.idle_hours)h" else "" end)",
    "verdict: \(.verdict)\(if .hint then " — " + .hint else "" end)"'
}

verdict_exit() {
  case "$(printf '%s' "$1" | jq -r .verdict)" in
    unclaimed | mine) return 0 ;;
    claimed) return 3 ;;
    *) return 1 ;;
  esac
}

# True when every fetch and push URL of origin is $repo, so git reads and
# writes reach the repository gh resolved (gh may follow a set-default upstream
# or GH_REPO, and a remote may push somewhere other than it fetches).
origin_is_repo() {
  local urls url
  urls="$(git remote get-url --all origin 2>/dev/null; git remote get-url --push --all origin 2>/dev/null)" || return 1
  [ -n "$urls" ] || return 1
  while IFS= read -r url; do
    url="${url%.git}"
    url="${url#*github.com[:/]}"
    [ "$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')" ] || return 1
  done <<< "$urls"
}

# True when tree $1 (GitHub's copy) holds exactly tree $2 (local): the same
# paths, types and contents, and the same modes except local 100755 published
# as 100644, the one difference gh-verified-push.sh introduces.
published_copy_of() {
  awk -F '\t' '
    NR == FNR { remote[$1] = $2; n++; next }
    { split(remote[$1], r, " "); split($2, l, " ")
      if (!($1 in remote) || r[2] != l[2] || r[3] != l[3] \
        || (r[1] != l[1] && !(l[1] == "100755" && r[1] == "100644"))) bad = 1
      m++ }
    END { exit (bad || m != n) }' \
    <(git ls-tree -r --format='%(path)%x09%(objectmode) %(objecttype) %(objectname)' "$1") \
    <(git ls-tree -r --format='%(path)%x09%(objectmode) %(objecttype) %(objectname)' "$2")
}

# True when $1..HEAD is plain local work: no merge commit and no commit the
# default branch tip ($default_tip) holds. A local rebase onto, or merge of,
# the default branch fails this, even when it keeps the published tree.
local_work_since() {
  [ -z "$(git rev-list --min-parents=2 --max-count=1 "$1..HEAD")" ] \
    && [ "$(git rev-list --count "$1..HEAD")" = "$(git rev-list --count "$1..HEAD" "^${default_tip}")" ]
}

# True when this checkout's HEAD or branch $1 once pointed at commit $2.
held_locally() {
  { git log -g --format=%H HEAD 2>/dev/null; git log -g --format=%H "refs/heads/$1" 2>/dev/null; } | grep -x "$2" >/dev/null
}

# The Pull Request fields land decides on. Check runs report status plus
# conclusion; commit statuses report state.
land_pr_json() {
  gh api graphql -f owner="${repo%%/*}" -f name="${repo#*/}" -F n="$land_pr" -f query='
    query($owner: String!, $name: String!, $n: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $n) {
          number title state isDraft isCrossRepository baseRefName headRefName headRefOid mergeStateStatus
          autoMergeRequest { enabledAt }
          mergeCommit { oid }
          closingIssuesReferences(first: 20) { nodes { number } }
          commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { totalCount nodes {
            ... on CheckRun { name status conclusion isRequired(pullRequestNumber: $n) }
            ... on StatusContext { context state isRequired(pullRequestNumber: $n) }
          } } } } } }
        }
      }
    }' --jq '.data.repository.pullRequest
      | .closingIssuesReferences = [.closingIssuesReferences.nodes[]]
      | .statusCheckRollup = [(.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // [])[]]
      | .checksComplete = ((.commits.nodes[0].commit.statusCheckRollup.contexts.totalCount // 0) <= (.statusCheckRollup | length))
      | del(.commits)'
}

# Summarize the checks of a Pull Request snapshot: the pending count and the
# failed checks that block. A failed required check always blocks; a failed
# optional check blocks unless --accept-failed names it as inherited.
land_checks() {
  printf '%s' "$1" | jq -c --argjson accepted "$accepted_failures" '
    [.statusCheckRollup[]? | {
      name: (.name // .context // "check"),
      required: (.isRequired == true),
      pending: ((.status // "COMPLETED") != "COMPLETED" or ((.state // "") | IN("PENDING", "EXPECTED"))),
      failed: (((.conclusion // "") | IN("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"))
        or ((.state // "") | IN("FAILURE", "ERROR")))
    }]
    | {pending: map(select(.pending)) | length,
       failed: [.[] | select(.failed and (.required or (.name | IN($accepted[]) | not))) | .name],
       accepted: [.[] | select(.failed and (.required | not) and (.name | IN($accepted[]))) | .name]}'
}

# Withdraw a queued auto-merge so no later head can land through it.
land_withdraw() {
  if [ "$(printf '%s' "$1" | jq -r '.autoMergeRequest != null')" = true ]; then
    gh pr merge "$land_pr" -R "$repo" --disable-auto >/dev/null \
      && printf 'issue-lane: withdrew the queued auto-merge on #%s\n' "$land_pr" >&2
  fi
}

# Confirm a merged Pull Request: the merge commit is on the default branch and
# the Issue closed. Only then delete the claim branch on GitHub. Safe to rerun.
land_finish() {
  local snapshot="$1" merged_head merge_sha branch branch_sha on_default=false issue_now tries deleted=false
  merged_head="$(printf '%s' "$snapshot" | jq -r .headRefOid)"
  merge_sha="$(printf '%s' "$snapshot" | jq -r '.mergeCommit.oid // empty')"
  branch="$(printf '%s' "$snapshot" | jq -r .headRefName)"
  if [ "$merged_head" != "$land_head" ]; then
    printf 'issue-lane: #%s merged head %s, not the reviewed %s\n' "$land_pr" "$merged_head" "$land_head" >&2
    exit 4
  fi
  if [ -n "$merge_sha" ]; then
    case "$(gh api "repos/${repo}/compare/${merge_sha}...${default_branch}" --jq .status 2>/dev/null || true)" in
      identical | ahead) on_default=true ;;
    esac
  fi
  issue_now="$issue_state"
  for tries in 1 2 3 4 5; do
    issue_now="$(gh issue view "$issue" --json state --jq .state)"
    [ "$issue_now" = CLOSED ] && break
    [ "$tries" -lt 5 ] && sleep "$(( POLL_SECONDS < 10 ? POLL_SECONDS : 10 ))"
  done
  # Delete only our own claim branch, and only while it still points at the
  # merged head; commits pushed after the merge stay.
  if [ "$on_default" = true ] && [ "$issue_now" = CLOSED ] && [ "$branch" != "$default_branch" ] \
    && [ "$(printf '%s' "$snapshot" | jq -r .isCrossRepository)" = false ] \
    && printf '%s' "$branch" | grep -Eq "^[^/]+/${issue}(-[^/]*)?\$"; then
    # ls-remote exits 2 only when the ref is absent; the lease makes the
    # delete conditional on the merged head at the remote, in one update.
    if ! origin_is_repo; then
      printf 'issue-lane: origin is not %s; leaving %s\n' "$repo" "$branch" >&2
    elif branch_sha="$(git ls-remote --exit-code origin "refs/heads/${branch}")"; then
      branch_sha="${branch_sha%%[[:space:]]*}"
      if [ "$branch_sha" = "$merged_head" ]; then
        git push --quiet --force-with-lease="refs/heads/${branch}:${merged_head}" origin ":refs/heads/${branch}" \
          && deleted=true
      else
        printf 'issue-lane: %s moved to %s after the merge; leaving it\n' "$branch" "$branch_sha" >&2
      fi
    elif [ "$?" -eq 2 ]; then
      deleted=true
    else
      printf 'issue-lane: could not read %s on origin\n' "$branch" >&2
    fi
  fi
  jq -n --arg repo "$repo" --argjson issue "$issue" --argjson pr "$land_pr" --arg head "$merged_head" \
    --arg merge "$merge_sha" --argjson on_default "$on_default" --arg issue_state "$issue_now" \
    --arg branch "$branch" --argjson deleted "$deleted" \
    '{repo: $repo, issue: $issue, pr: $pr, verdict: "merged", head: $head, merge_commit: $merge,
      on_default_branch: $on_default, issue_state: $issue_state, branch: $branch, branch_deleted: $deleted}'
  if [ "$on_default" != true ] || [ "$issue_now" != CLOSED ] || [ "$deleted" != true ]; then
    printf 'issue-lane: #%s merged, but unconfirmed: on %s %s, Issue #%s %s, branch deleted %s; land again to recheck\n' \
      "$land_pr" "$default_branch" "$on_default" "$issue" "$issue_now" "$deleted" >&2
    exit 7
  fi
  exit 0
}

# Stop on a merged or closed Pull Request, a non-default base, or a moved
# head; return otherwise.
land_guard() {
  local snapshot="$1"
  case "$(printf '%s' "$snapshot" | jq -r .state)" in
    MERGED) land_finish "$snapshot" ;;
    CLOSED) fail "Pull Request #${land_pr} is closed without merging" ;;
  esac
  [ "$(printf '%s' "$snapshot" | jq -r .baseRefName)" = "$default_branch" ] \
    || fail "#${land_pr} targets $(printf '%s' "$snapshot" | jq -r .baseRefName), not ${default_branch}; land lands lanes on the default branch only"
  if [ "$(printf '%s' "$snapshot" | jq -r .headRefOid)" != "$land_head" ]; then
    land_withdraw "$snapshot"
    printf 'issue-lane: #%s head is %s, not the reviewed %s; review and land the new head\n' \
      "$land_pr" "$(printf '%s' "$snapshot" | jq -r .headRefOid)" "$land_head" >&2
    exit 4
  fi
}

case "$command_name" in
  check)
    report="$(report_json)"
    print_report "$report"
    verdict_exit "$report"
    ;;

  claim)
    report="$(report_json)"
    case "$(printf '%s' "$report" | jq -r .verdict)" in
      unclaimed) ;;
      mine)
        print_report "$report" >&2
        printf 'issue-lane: #%s is already your lane; resume it\n' "$issue" >&2
        exit 0
        ;;
      *)
        print_report "$report" >&2
        printf 'issue-lane: refusing to claim #%s\n' "$issue" >&2
        exit 3
        ;;
    esac
    capacity="$(live_capacity_json)" || fail "cannot load the listings for lane capacity"
    if [ "$(printf '%s' "$capacity" | jq .remaining)" -eq 0 ]; then
      print_capacity "$capacity" >&2
      printf 'issue-lane: lane limit reached; land or release a lane before claiming #%s\n' "$issue" >&2
      exit 3
    fi
    base_sha="$(gh api "repos/${repo}/git/ref/heads/${default_branch}" --jq .object.sha)"
    printf 'claim plan: branch %s from %s@%s, assign %s to #%s, lane owner %s\n' \
      "$lane_branch" "$default_branch" "${base_sha:0:12}" "$login" "$issue" "$lane_agent" >&2
    if [ "$dry_run" = true ]; then
      printf 'dry run; no GitHub mutation.\n' >&2
      exit 0
    fi
    if ! gh api -X POST "repos/${repo}/git/refs" \
      -f ref="refs/heads/${lane_branch}" -f sha="$base_sha" >/dev/null 2>&1; then
      printf 'issue-lane: could not create %s; another lane probably claimed #%s first:\n' \
        "$lane_branch" "$issue" >&2
      print_report "$(report_json)" >&2
      exit 3
    fi
    # Claims racing for the last slot can all pass the check above; recount
    # with this branch included and back out if the limit is now exceeded.
    # Every racer may back out, which leaves the slot free to claim again; the
    # limit is never exceeded.
    recounted=true
    capacity="$(live_capacity_json)" || recounted=false
    if [ "$recounted" = false ] || [ "$(printf '%s' "$capacity" | jq .used)" -gt "$LANE_LIMIT" ]; then
      [ "$recounted" = false ] || print_capacity "$capacity" >&2
      gh api -X DELETE "repos/${repo}/git/refs/heads/${lane_branch}" >/dev/null \
        || fail "created ${lane_branch} but could not confirm lane capacity or delete it; delete it by hand"
      printf 'issue-lane: lane limit exceeded or unconfirmed; deleted %s again\n' "$lane_branch" >&2
      exit 3
    fi
    # The ref is ours; record who holds it. Without the marker nobody could
    # prove ownership, so undo the ref rather than leave an orphan claim.
    token="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    token_hash="$(printf '%s' "$token" | sha256_short)"
    marker_body="Lane claimed by \`${lane_agent}\` on \`${lane_branch}\`.

<!-- issue-lane-claim agent=${lane_agent} token-sha256=${token_hash} -->"
    undo_claim() {
      gh api -X DELETE "repos/${repo}/git/refs/heads/${lane_branch}" >/dev/null 2>&1 || true
      fail "$1; claim undone, retry"
    }
    # Winning the ref proves no live lane exists, so any older marker is a
    # leftover (a landed or reopened lane); drop it so ours is the only one.
    # Any failure here undoes the ref: a claim must not go out next to an old marker.
    stale_ids="$(gh api "repos/${repo}/issues/${issue}/comments" --paginate \
      --jq '.[] | select(.body | test("<!-- issue-lane-claim ")) | .id')" \
      || undo_claim "could not list owner markers on #${issue}"
    for stale_id in $stale_ids; do
      gh api -X DELETE "repos/${repo}/issues/comments/${stale_id}" >/dev/null \
        || undo_claim "could not remove the stale owner marker ${stale_id} from #${issue}"
    done
    if ! gh issue comment "$issue" --body "$marker_body" >/dev/null; then
      # The comment may exist despite the error; roll back only when a lookup
      # proves it does not, and keep the claim when even that is uncertain.
      if ! bodies="$(gh api "repos/${repo}/issues/${issue}/comments" --paginate --jq '.[].body')"; then
        printf 'issue-lane: owner marker on #%s unverified; claim kept. LANE_TOKEN=%s\n' "$issue" "$token" >&2
        exit 1
      fi
      printf '%s' "$bodies" | grep -q "token-sha256=${token_hash} " \
        || undo_claim "could not record the lane owner on #${issue}"
    fi
    # The assignment is a visible hint only; never lose the token over it.
    gh issue edit "$issue" --add-assignee "@me" >/dev/null \
      || printf 'issue-lane: could not assign %s to #%s; the claim stands\n' "$login" "$issue" >&2
    printf 'issue-lane: keep the token in your own session and pass LANE_TOKEN=<token> to check, release, push, and land.\n' >&2
    printf 'issue-lane: never write it on GitHub, in the repository, or in a path another agent reads.\n' >&2
    jq -n --arg repo "$repo" --argjson issue "$issue" --arg branch "$lane_branch" \
      --arg base "$base_sha" --arg assignee "$login" --arg agent "$lane_agent" --arg token "$token" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{repo: $repo, issue: $issue, branch: $branch, base_sha: $base, assignee: $assignee,
        agent: $agent, token: $token, claimed_at: $at}'
    ;;

  release)
    report="$(report_json)"
    # Any existing claim that is not provably ours, open or closed, with or
    # without an owner marker, needs the maintainer's --yes.
    if [ "$confirm" != true ] && printf '%s' "$report" \
      | jq -e '(.mine | not) and (.verdict == "claimed" or (.claim_branches | length) > 0 or .owner != null)' >/dev/null; then
      print_report "$report" >&2
      fail "#${issue} is not your lane; release with its LANE_TOKEN, or pass --yes with the maintainer's approval"
    fi
    marker_id="$(printf '%s' "$report" | jq -r '.owner.marker_id // empty')"
    if [ "$(printf '%s' "$report" | jq '.open_prs | length')" -gt 0 ]; then
      print_report "$report" >&2
      fail "an open Pull Request exists; close it first or let it land"
    fi
    has_lane_branch="$(printf '%s' "$report" | jq --arg b "$lane_branch" '.claim_branches | index($b) != null')"
    if [ "$has_lane_branch" = true ] && [ "$confirm" != true ]; then
      ahead="$(gh api "repos/${repo}/compare/${default_branch}...${lane_branch}" --jq .ahead_by)"
      [ "$ahead" -eq 0 ] \
        || fail "${lane_branch} has ${ahead} commit(s) beyond ${default_branch}; pass --yes to delete it anyway"
    fi
    # Remove the marker read above before deleting anything else. It doubles as
    # the release fence: a second release with the same token fails here,
    # before it can delete a branch that a replacement claim created in
    # between. The cost is deliberate: a release interrupted after this point
    # leaves an ownerless branch that only the maintainer's --yes removes.
    if [ -n "$marker_id" ]; then
      gh api -X DELETE "repos/${repo}/issues/comments/${marker_id}" >/dev/null \
        || fail "could not remove lane owner marker ${marker_id}; another release may have run; check again"
      printf 'removed lane owner marker %s from #%s\n' "$marker_id" "$issue" >&2
    fi
    if [ "$has_lane_branch" = true ]; then
      gh api -X DELETE "repos/${repo}/git/refs/heads/${lane_branch}" >/dev/null
      printf 'deleted branch %s\n' "$lane_branch" >&2
    fi
    if printf '%s' "$report" | jq -e --arg me "$login" '.assignment.assignees | index($me)' >/dev/null; then
      gh issue edit "$issue" --remove-assignee "@me" >/dev/null
      printf 'removed assignee %s from #%s\n' "$login" "$issue" >&2
    fi
    issue_json="$(fetch_issue)"
    report="$(report_json)"
    print_report "$report"
    ;;

  push)
    require_mine
    current="$(git rev-parse --abbrev-ref HEAD)"
    printf '%s' "$current" | grep -Eq "^[^/]+/${issue}(-[^/]*)?\$" \
      || fail "check out the lane branch of #${issue} first (on ${current})"
    origin_is_repo || fail "origin is not ${repo}; push from a checkout of ${repo}"
    remote_tip="$(git ls-remote --exit-code origin "refs/heads/${current}")" \
      || fail "${current} is not readable on origin; claim #${issue} first"
    remote_tip="${remote_tip%%[[:space:]]*}"
    default_tip="$(git ls-remote --exit-code origin "refs/heads/${default_branch}")" \
      || fail "${default_branch} is not readable on origin"
    default_tip="${default_tip%%[[:space:]]*}"
    git fetch --quiet origin "$remote_tip" "$default_tip"
    scratch="lane-publish/${issue}/rebase"
    if [ "$rebased" = true ]; then
      # A scratch branch left by an earlier push --rebased is ours: require_mine
      # proved this lane is the Issue's only owner.
      gh api -X DELETE "repos/${repo}/git/refs/heads/${scratch}" >/dev/null 2>&1 || true
    fi
    recover="verified publishing cannot publish a merge. Recover: rebase onto ${default_branch} instead and run push ${issue} --rebased"
    # The branch already holds HEAD: either nothing changed since the last
    # publish (identical tree), or a publish stopped before syncing and left
    # GitHub's copy of HEAD on top of local history. Adopt the verified tip
    # only when the commits it replaces are plain local work, so a local
    # rebase or merge of the default branch that happens to keep the
    # published tree is never reset away.
    if { git merge-base --is-ancestor "$remote_tip" HEAD \
        && [ "$(git rev-parse "${remote_tip}^{tree}")" = "$(git rev-parse 'HEAD^{tree}')" ] \
        && local_work_since "$remote_tip"; } \
      || { git merge-base --is-ancestor "${remote_tip}^" HEAD && published_copy_of "$remote_tip" HEAD \
        && local_work_since "${remote_tip}^"; }; then
      [ "$(gh api "repos/${repo}/commits/${remote_tip}" --jq '.commit.verification.verified')" = true ] \
        || fail "${current} holds HEAD as ${remote_tip:0:12}, but GitHub does not show it Verified"
      [ -z "$(git status --porcelain)" ] || fail "working tree is dirty; commit or discard before syncing"
      git reset --quiet --hard "$remote_tip"
      printf 'issue-lane: %s already holds HEAD as %s; synced the checkout\n' "$current" "${remote_tip:0:12}" >&2
      printf '%s\n' "$remote_tip"
      exit 0
    fi
    # Publish only on top of what is on GitHub: a stale or rebased checkout
    # would overwrite or misplace published commits, and a merge commit
    # cannot be published at all.
    if git merge-base --is-ancestor "$remote_tip" HEAD; then
      [ -z "$(git rev-list --min-parents=2 --max-count=1 "${remote_tip}..HEAD")" ] \
        || fail "local history of ${current} merges another branch after ${remote_tip:0:12}; ${recover}"
      bash "${KIT_ROOT}/scripts/gh-verified-push.sh" --repo "$repo" --branch "$current" \
        --expected-oid "$remote_tip" --sync-local
      exit 0
    fi
    [ "$rebased" = true ] \
      || fail "local HEAD does not descend from ${current} on origin (${remote_tip:0:12}); it was rebased or rewritten after the publish. If it was rebased onto ${default_branch}, run push ${issue} --rebased"
    held_locally "$current" "$remote_tip" \
      || fail "${current} on origin (${remote_tip:0:12}) was never held by this checkout; fetch and rebase the published work before push --rebased"
    new_base="$(git merge-base HEAD "$default_tip")" \
      || fail "local HEAD shares no history with ${default_branch}"
    local_work_since "$new_base" \
      || fail "local history of ${current} merges another branch after ${new_base:0:12}; ${recover}"
    [ "$(git rev-parse "${new_base}^{tree}")" != "$(git rev-parse 'HEAD^{tree}')" ] \
      || fail "local HEAD holds no change on top of ${default_branch} (${new_base:0:12}); nothing to publish"
    [ -z "$(git status --porcelain)" ] || fail "working tree is dirty; commit or discard before publishing"
    # Step 1: one verified commit with parent new_base, off the Pull Request.
    published="$(bash "${KIT_ROOT}/scripts/gh-verified-push.sh" --repo "$repo" --branch "$scratch" \
      --create-branch-from "$new_base")"
    printf '%s' "$published" | grep -Eq '^[0-9a-f]{40}$' || fail "publishing ${scratch} returned no commit"
    # Step 2: move the claim branch onto it, only from the tip this checkout held.
    repo_id="$(gh api "repos/${repo}" --jq .node_id)"
    jq -n --arg id "$repo_id" --arg ref "refs/heads/${current}" --arg before "$remote_tip" --arg after "$published" '{
      query: "mutation($input: UpdateRefsInput!) { updateRefs(input: $input) { clientMutationId } }",
      variables: {input: {repositoryId: $id, refUpdates: [{name: $ref, beforeOid: $before, afterOid: $after, force: true}]}}}' \
      | gh api graphql --input - | jq -e '(.errors // []) | length == 0' >/dev/null \
      || fail "GitHub did not confirm moving ${current} from ${remote_tip:0:12} to ${published:0:12}; run push ${issue} --rebased again, which adopts the move if it happened and refuses if ${current} moved elsewhere"
    gh api -X DELETE "repos/${repo}/git/refs/heads/${scratch}" >/dev/null 2>&1 \
      || printf 'issue-lane: could not delete %s; the next push %s --rebased deletes it\n' "$scratch" "$issue" >&2
    git fetch --quiet origin "$published"
    git reset --quiet --hard "$published"
    printf 'issue-lane: moved %s from %s onto %s at %s\n' "$current" "${remote_tip:0:12}" "${default_branch}" "${new_base:0:12}" >&2
    printf '%s\n' "$published"
    ;;

  land)
    printf '%s' "$land_pr" | grep -Eq '^[0-9]+$' || fail "land needs --pr <number>"
    [ -n "$land_head" ] || land_head="$(git rev-parse HEAD)"
    printf '%s' "$land_head" | grep -Eq '^[0-9a-f]{40}$' || fail "land needs --head <full reviewed commit SHA>"
    printf '%s' "$timeout_min" | grep -Eq '^[0-9]+$' || fail "--timeout-min needs whole minutes"
    require_mine
    snapshot="$(land_pr_json)"
    land_guard "$snapshot"
    if [ "$(printf '%s' "$snapshot" | jq -r '.autoMergeRequest != null')" = true ]; then
      land_withdraw "$snapshot"
      snapshot="$(land_pr_json)"
      land_guard "$snapshot"
      [ "$(printf '%s' "$snapshot" | jq -r '.autoMergeRequest == null')" = true ] \
        || fail "could not withdraw the queued auto-merge on #${land_pr}"
    fi
    [ "$(printf '%s' "$snapshot" | jq -r .isDraft)" = false ] || fail "#${land_pr} is a draft; mark it ready first"
    printf '%s' "$snapshot" | jq -e --argjson issue "$issue" '.closingIssuesReferences | map(.number) | index($issue)' >/dev/null \
      || fail "#${land_pr} does not close Issue #${issue}; add a visible Closes line"
    printf 'issue-lane: landing #%s at %s once its checks pass\n' "$land_pr" "${land_head:0:12}" >&2

    deadline=$(( $(date +%s) + timeout_min * 60 ))
    while :; do
      # Decide only on a complete view of the checks.
      [ "$(printf '%s' "$snapshot" | jq -r '.checksComplete != false')" = true ] \
        || { printf 'issue-lane: #%s has more checks than land reads; merge it by hand\n' "$land_pr" >&2; exit 5; }
      checks="$(land_checks "$snapshot")"
      merge_state="$(printf '%s' "$snapshot" | jq -r .mergeStateStatus)"
      pending="$(printf '%s' "$checks" | jq .pending)"
      failed="$(printf '%s' "$checks" | jq -r '.failed | join(", ")')"
      if [ "$pending" -eq 0 ] && [ -n "$failed" ]; then
        printf 'issue-lane: #%s blocked by failed checks: %s; classify them under the landing rules (name an optional check that also fails on %s with --accept-failed)\n' "$land_pr" "$failed" "$default_branch" >&2
        exit 5
      fi
      case "$merge_state" in
        DIRTY | BEHIND)
          printf 'issue-lane: #%s is %s against %s; refresh the branch\n' "$land_pr" "$merge_state" "$default_branch" >&2
          exit 5
          ;;
        CLEAN | HAS_HOOKS | UNSTABLE)
          # UNSTABLE means only optional checks failed; reaching here, each one
          # was accepted, or the failed-checks guard above would have stopped.
          if [ "$pending" -eq 0 ]; then
            accepted="$(printf '%s' "$checks" | jq -r '.accepted | join(", ")')"
            [ -z "$accepted" ] || printf 'issue-lane: landing #%s over accepted inherited failures: %s\n' "$land_pr" "$accepted" >&2
            title="$(printf '%s' "$snapshot" | jq -r .title)"
            # The REST merge either merges now or fails; it never queues. The
            # reviewed head is its precondition, so a moved head is refused.
            if ! merge_out="$(gh api -X PUT "repos/${repo}/pulls/${land_pr}/merge" \
              -f merge_method=squash -f sha="$land_head" -f commit_title="${title} (#${land_pr})" 2>&1)"; then
              snapshot="$(land_pr_json)"
              land_guard "$snapshot"
              printf 'issue-lane: merge of #%s refused: %s\n' "$land_pr" "$merge_out" >&2
              exit 5
            fi
            # Confirm the accepted merge before any deadline can end the watch.
            for tries in 1 2 3 4 5; do
              snapshot="$(land_pr_json)"
              land_guard "$snapshot"
              [ "$tries" -lt 5 ] && sleep "$(( POLL_SECONDS < 10 ? POLL_SECONDS : 10 ))"
            done
            printf 'issue-lane: GitHub accepted the merge of #%s but does not show it merged; land again to recheck\n' "$land_pr" >&2
            exit 7
          fi
          ;;
      esac
      if [ "$(date +%s)" -ge "$deadline" ]; then
        printf 'issue-lane: #%s not mergeable after %s min (merge state %s, %s pending); land again to keep watching\n' \
          "$land_pr" "$timeout_min" "$merge_state" "$pending" >&2
        exit 6
      fi
      sleep "$POLL_SECONDS"
      snapshot="$(land_pr_json)"
      land_guard "$snapshot"
    done
    ;;
esac
