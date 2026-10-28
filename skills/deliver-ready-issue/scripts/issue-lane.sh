#!/usr/bin/env bash
# Inspect, claim, release, publish, or land the delivery lane of one GitHub
# Issue, or report the repository's lane capacity.
#
# A lane claim lives on GitHub so agents on different machines see it:
#   1. the branch <type>/<issue>, created from the default branch with an
#      atomic ref creation (POST /git/refs fails when the ref exists, so the
#      first claimant wins and every other claimant sees "claimed");
#   2. the authenticated login assigned to the Issue, visible in the Issue
#      list and timestamped by the Issue timeline.
# Open Pull Requests that reference the Issue and any branch matching
# */<issue> or */<issue>-* count as claims too.
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
# local HEAD equals the Pull Request head afterwards.
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
#   bash issue-lane.sh claim <issue> [--dry-run]
#   bash issue-lane.sh release <issue> [--yes]
#   bash issue-lane.sh push <issue>
#   bash issue-lane.sh land <issue> --pr <number> [--head <sha>] [--timeout-min <n>]
#
# Exit codes: 0 unclaimed, done, capacity left, or merged and confirmed; 3
# claimed by another lane or no lane capacity left; 4 head moved (review and
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
land_pr=""
land_head=""
timeout_min=45
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) json_output=true ;;
    --dry-run) dry_run=true ;;
    --yes) confirm=true ;;
    --self-test) self_test=true ;;
    --pr | --head | --timeout-min)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --pr) land_pr="$2" ;;
        --head) land_head="$2" ;;
        --timeout-min) timeout_min="$2" ;;
      esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done

case "$command_name" in
  push | land)
    [ "$json_output" = false ] && [ "$dry_run" = false ] && [ "$confirm" = false ] \
      || fail "${command_name} does not take --json, --dry-run, or --yes"
    ;;
  capacity)
    [ "$dry_run" = false ] && [ "$confirm" = false ] || fail "capacity does not take --dry-run or --yes"
    ;;
esac
[ "$command_name" = land ] || [ -z "$land_pr$land_head" ] || fail "--pr and --head belong to land"
[ "$command_name" = capacity ] || [ "$self_test" = false ] || fail "--self-test belongs to capacity"
printf '%s' "$LANE_LIMIT" | grep -Eq '^[1-9][0-9]*$' || fail "ISSUE_LANE_LIMIT must be a positive whole number"

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

issue_json="$(gh issue view "$issue" --json number,title,state,labels,assignees,closedByPullRequestsReferences)"
issue_state="$(printf '%s' "$issue_json" | jq -r .state)"
issue_title="$(printf '%s' "$issue_json" | jq -r .title)"

# Derive the lane type deterministically so every machine computes the same
# branch: Conventional Commit type in the title (bug -> fix), then the type
# label, then chore.
lane_type() {
  local from_title
  from_title="$(printf '%s' "$issue_title" | sed -nE 's/^([a-z]+)(\([^)]*\))?!?:.*/\1/p')"
  case "$from_title" in
    bug) printf 'fix' ; return ;;
    "") ;;
    *) printf '%s' "$from_title" ; return ;;
  esac
  if printf '%s' "$issue_json" | jq -e '.labels[] | select(.name == "bug")' >/dev/null; then
    printf 'fix'
  elif printf '%s' "$issue_json" | jq -e '.labels[] | select(.name == "enhancement")' >/dev/null; then
    printf 'feat'
  elif printf '%s' "$issue_json" | jq -e '.labels[] | select(.name == "documentation")' >/dev/null; then
    printf 'docs'
  else
    printf 'chore'
  fi
}
lane_branch="$(lane_type)/${issue}"

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
  local last_assigned now_epoch then_epoch age_hours
  last_assigned="$(gh api "repos/${repo}/issues/${issue}/timeline" --paginate \
    | jq -rs '[.[] | .[]? // empty] | map(select(.event == "assigned")) | sort_by(.created_at) | last | .created_at // empty')"
  age_hours=null
  if [ -n "$last_assigned" ]; then
    now_epoch="$(date -u +%s)"
    then_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_assigned" +%s 2>/dev/null \
      || date -u -d "$last_assigned" +%s)"
    age_hours=$(( (now_epoch - then_epoch) / 3600 ))
  fi
  printf '%s' "$issue_json" | jq -c --arg at "${last_assigned:-}" --argjson age "$age_hours" \
    '{assignees: [.assignees[].login], last_assigned_at: (if $at == "" then null else $at end), age_hours: $age}'
}

report_json() {
  local branches prs assignment verdict hint
  branches="$(claim_branches_json)"
  prs="$(open_prs_json "$branches")"
  assignment="$(assignment_json)"
  verdict=unclaimed
  hint=""
  if [ "$issue_state" != "OPEN" ]; then
    verdict=closed
  elif [ "$(printf '%s' "$prs" | jq length)" -gt 0 ] || [ "$(printf '%s' "$branches" | jq length)" -gt 0 ]; then
    verdict=claimed
  elif [ "$(printf '%s' "$assignment" | jq '.assignees | length')" -gt 0 ]; then
    if [ "$(printf '%s' "$assignment" | jq '.age_hours // 0')" -lt "$STALE_HOURS" ]; then
      verdict=claimed
    else
      hint="assignment older than ${STALE_HOURS}h without a branch or Pull Request; ask the maintainer before claiming"
    fi
  fi
  jq -n \
    --arg repo "$repo" --argjson issue "$issue" --arg title "$issue_title" --arg state "$issue_state" \
    --arg lane_branch "$lane_branch" --argjson branches "$branches" --argjson prs "$prs" \
    --argjson assignment "$assignment" --arg verdict "$verdict" --arg hint "$hint" \
    '{repo: $repo, issue: $issue, title: $title, state: $state, lane_branch: $lane_branch,
      claim_branches: $branches, open_prs: $prs, assignment: $assignment,
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
    "verdict: \(.verdict)\(if .hint then " — " + .hint else "" end)"'
}

verdict_exit() {
  case "$(printf '%s' "$1" | jq -r .verdict)" in
    unclaimed) return 0 ;;
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

# The Pull Request fields land decides on. Check runs report status plus
# conclusion; commit statuses report state.
land_pr_json() {
  gh pr view "$land_pr" -R "$repo" --json \
    number,state,isDraft,isCrossRepository,baseRefName,headRefName,headRefOid,mergeStateStatus,autoMergeRequest,mergeCommit,statusCheckRollup,closingIssuesReferences
}

# Summarize the checks of a Pull Request snapshot: pending and failed counts
# and the failed check names.
land_checks() {
  printf '%s' "$1" | jq -c '
    [.statusCheckRollup[]? | {
      name: (.name // .context // "check"),
      pending: ((.status // "COMPLETED") != "COMPLETED" or ((.state // "") | IN("PENDING", "EXPECTED"))),
      failed: (((.conclusion // "") | IN("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"))
        or ((.state // "") | IN("FAILURE", "ERROR")))
    }]
    | {pending: map(select(.pending)) | length,
       failed: [.[] | select(.failed) | .name]}'
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
    if ! verdict_exit "$report"; then
      print_report "$report" >&2
      printf 'issue-lane: refusing to claim #%s\n' "$issue" >&2
      exit 3
    fi
    capacity="$(live_capacity_json)" || fail "cannot load the listings for lane capacity"
    if [ "$(printf '%s' "$capacity" | jq .remaining)" -eq 0 ]; then
      print_capacity "$capacity" >&2
      printf 'issue-lane: lane limit reached; land or release a lane before claiming #%s\n' "$issue" >&2
      exit 3
    fi
    base_sha="$(gh api "repos/${repo}/git/ref/heads/${default_branch}" --jq .object.sha)"
    printf 'claim plan: branch %s from %s@%s, assign %s to #%s\n' \
      "$lane_branch" "$default_branch" "${base_sha:0:12}" "$login" "$issue" >&2
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
    gh issue edit "$issue" --add-assignee "@me" >/dev/null
    jq -n --arg repo "$repo" --argjson issue "$issue" --arg branch "$lane_branch" \
      --arg base "$base_sha" --arg assignee "$login" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{repo: $repo, issue: $issue, branch: $branch, base_sha: $base, assignee: $assignee, claimed_at: $at}'
    ;;

  release)
    report="$(report_json)"
    if [ "$(printf '%s' "$report" | jq '.open_prs | length')" -gt 0 ]; then
      print_report "$report" >&2
      fail "an open Pull Request exists; close it first or let it land"
    fi
    if printf '%s' "$report" | jq -e --arg b "$lane_branch" '.claim_branches | index($b)' >/dev/null; then
      ahead="$(gh api "repos/${repo}/compare/${default_branch}...${lane_branch}" --jq .ahead_by)"
      if [ "$ahead" -gt 0 ] && [ "$confirm" != true ]; then
        fail "${lane_branch} has ${ahead} commit(s) beyond ${default_branch}; pass --yes to delete it anyway"
      fi
      gh api -X DELETE "repos/${repo}/git/refs/heads/${lane_branch}" >/dev/null
      printf 'deleted branch %s\n' "$lane_branch" >&2
    fi
    if printf '%s' "$report" | jq -e --arg me "$login" '.assignment.assignees | index($me)' >/dev/null; then
      gh issue edit "$issue" --remove-assignee "@me" >/dev/null
      printf 'removed assignee %s from #%s\n' "$login" "$issue" >&2
    fi
    print_report "$(report_json)"
    ;;

  push)
    current="$(git rev-parse --abbrev-ref HEAD)"
    printf '%s' "$current" | grep -Eq "^[^/]+/${issue}(-[^/]*)?\$" \
      || fail "check out the lane branch of #${issue} first (on ${current})"
    origin_is_repo || fail "origin is not ${repo}; push from a checkout of ${repo}"
    remote_tip="$(git ls-remote --exit-code origin "refs/heads/${current}")" \
      || fail "${current} is not readable on origin; claim #${issue} first"
    remote_tip="${remote_tip%%[[:space:]]*}"
    git fetch --quiet origin "$remote_tip"
    # The branch already holds HEAD: either nothing changed since the last
    # publish (identical tree), or a publish stopped before syncing and left
    # GitHub's copy of HEAD on top of local history. Adopt the verified tip.
    if { git merge-base --is-ancestor "$remote_tip" HEAD \
        && [ "$(git rev-parse "${remote_tip}^{tree}")" = "$(git rev-parse 'HEAD^{tree}')" ]; } \
      || { git merge-base --is-ancestor "${remote_tip}^" HEAD && published_copy_of "$remote_tip" HEAD; }; then
      [ "$(gh api "repos/${repo}/commits/${remote_tip}" --jq '.commit.verification.verified')" = true ] \
        || fail "${current} holds HEAD as ${remote_tip:0:12}, but GitHub does not show it Verified"
      [ -z "$(git status --porcelain)" ] || fail "working tree is dirty; commit or discard before syncing"
      git reset --quiet --hard "$remote_tip"
      printf 'issue-lane: %s already holds HEAD as %s; synced the checkout\n' "$current" "${remote_tip:0:12}" >&2
      printf '%s\n' "$remote_tip"
      exit 0
    fi
    # Publish only on top of what is on GitHub: a stale or rebased checkout
    # would overwrite or misplace published commits.
    git merge-base --is-ancestor "$remote_tip" HEAD \
      || fail "local HEAD does not descend from ${current} on origin (${remote_tip:0:12}); verified publishing cannot rewrite history"
    bash "${KIT_ROOT}/scripts/gh-verified-push.sh" --repo "$repo" --branch "$current" \
      --expected-oid "$remote_tip" --sync-local
    ;;

  land)
    printf '%s' "$land_pr" | grep -Eq '^[0-9]+$' || fail "land needs --pr <number>"
    [ -n "$land_head" ] || land_head="$(git rev-parse HEAD)"
    printf '%s' "$land_head" | grep -Eq '^[0-9a-f]{40}$' || fail "land needs --head <full reviewed commit SHA>"
    printf '%s' "$timeout_min" | grep -Eq '^[0-9]+$' || fail "--timeout-min needs whole minutes"
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
      checks="$(land_checks "$snapshot")"
      merge_state="$(printf '%s' "$snapshot" | jq -r .mergeStateStatus)"
      pending="$(printf '%s' "$checks" | jq .pending)"
      failed="$(printf '%s' "$checks" | jq -r '.failed | join(", ")')"
      if [ "$pending" -eq 0 ] && [ -n "$failed" ]; then
        printf 'issue-lane: #%s blocked by failed checks: %s; classify them under the landing rules\n' "$land_pr" "$failed" >&2
        exit 5
      fi
      case "$merge_state" in
        DIRTY | BEHIND)
          printf 'issue-lane: #%s is %s against %s; refresh the branch\n' "$land_pr" "$merge_state" "$default_branch" >&2
          exit 5
          ;;
        CLEAN | HAS_HOOKS)
          if [ "$pending" -eq 0 ]; then
            # The REST merge either merges now or fails; it never queues. The
            # reviewed head is its precondition, so a moved head is refused.
            if ! merge_out="$(gh api -X PUT "repos/${repo}/pulls/${land_pr}/merge" \
              -f merge_method=squash -f sha="$land_head" 2>&1)"; then
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
