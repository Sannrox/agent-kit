#!/usr/bin/env bash
# Compute the dependency frontier of a repository's open Issues and, with
# --apply, keep their status:ready / status:blocked labels true.
#
# Dependencies come only from each Issue's "## GitHub dependencies" section
# ("### GitHub dependencies" in Issue forms); it ends at the next heading.
# The section is machine-evaluable only when it is exactly "none" or a plain
# list of references, one per line:
#   - #12            - Owner/repo#34 (delivered)
#   - https://github.com/Owner/repo/issues/56
# "(delivered)" is the only accepted note; any other parenthetical may be a
# gate, so it needs judgment too.
# Anything else (prose, gates such as "after the owner schedules it") needs
# judgment: the Issue is reported and never relabeled.
#
# Each Issue gets one state:
#   ready      every reference is an Issue closed as completed
#   blocked    at least one referenced Issue is open
#   anomalous  a reference is missing or the Issue depends on itself, or the
#              Issue is in or behind a same-repository dependency cycle
#              (labeled blocked; a cycle through another repository is
#              reported as plain blocked, which labels it the same)
#   judgment   prose, no section, a reference closed as not planned, or a
#              reference to a Pull Request
# "ready" means dependencies met. Claims (branches, Pull Requests,
# assignments) change between runs, so they are checked live with
# deliver-ready-issue/scripts/issue-lane.sh, never encoded in labels.
#
# --apply relabels only Issues that already carry status:ready or
# status:blocked and not status:triage: it keeps existing status labels true
# and never shapes an Issue. It changes only labels that differ, so a crashed
# or overlapping run is repaired by the next one. Both labels must exist.
# Without --apply nothing is written.
#
# Usage:
#   bash frontier.sh [--repo <owner/repo>] [--json] [--apply]
# Exit codes: 0 computed (and applied); 1 error, including any GitHub read
# that failed for a reason other than a missing Issue (fail closed: no label
# is written from a partial view). Requires an authenticated gh and jq.
set -euo pipefail

# Canonical source: Sannrox/agent-kit skills/advance-issue-frontier.

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit "${1:-2}"
}
fail() {
  printf 'frontier: %s\n' "$1" >&2
  exit 1
}

repo=""
json_output=false
apply=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$#" -ge 2 ] || usage; repo="$2"; shift ;;
    --json) json_output=true ;;
    --apply) apply=true ;;
    -h | --help) usage 0 ;;
    *) usage ;;
  esac
  shift
done
for tool in gh jq; do command -v "$tool" >/dev/null 2>&1 || fail "missing required command: $tool"; done
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || fail "cannot resolve the repository"

issues="$(gh issue list -R "$repo" --state open --limit 1000 --json number,title,labels,body)" \
  || fail "cannot list open Issues of ${repo}"
# A full page means the list may be truncated; never act on a partial view.
[ "$(jq length <<< "$issues")" -lt 1000 ] || fail "${repo} has 1000 or more open Issues; the list may be truncated"

# Parse each Issue's dependency section into {kind, refs}. kind is none,
# refs, prose, or missing.
parsed="$(jq -c --arg repo "$repo" '
  # capture yields nothing on a mismatch, so callers test is_ref first.
  def ref_re: "^[-*]\\s+(?:https://github\\.com/(?<u>[^/\\s]+/[^/\\s]+)/issues/|(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#)(?<n>[0-9]+)(?:\\s+\\(delivered\\))?\\s*$";
  def is_ref: test(ref_re);
  def ref_of($line):
    $line | capture(ref_re) | {repo: (.u // .r // $repo), number: (.n | tonumber)};
  map(
    ((.body // "") | gsub("\r"; "") | split("\n")) as $lines
    | ([$lines | to_entries[] | select(.value | test("^###?\\s+GitHub dependencies\\s*$"; "i")) | .key] | first) as $at
    | (if $at == null then null else
        [$lines[($at + 1):][]] as $rest
        | ([$rest | to_entries[] | select(.value | test("^#")) | .key] | first // ($rest | length)) as $end
        | [$rest[:$end][] | gsub("^\\s+|\\s+$"; "") | select(. != "")]
      end) as $section
    | {number, title, labels: [.labels[].name]}
      + (if $section == null then {kind: "missing", refs: []}
         elif ($section | length) == 1 and ($section[0] | test("^([-*]\\s+)?none\\.?$"; "i")) then {kind: "none", refs: []}
         elif ($section | length) > 0 and all($section[]; is_ref) then {kind: "refs", refs: [$section[] | ref_of(.)]}
         else {kind: "prose", refs: []} end))
' <<< "$issues")"

# Resolve every distinct reference once. A missing Issue is data; any other
# failure stops the run.
resolved='{}'
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  err="$(mktemp)"
  if out="$(gh api "repos/${ref%#*}/issues/${ref##*#}" --jq '{state, reason: .state_reason, pr: (.pull_request != null)}' 2>"$err")"; then
    resolved="$(jq -c --arg k "$ref" --argjson v "$out" '.[$k] = $v' <<< "$resolved")"
  elif grep -q 'HTTP 404' "$err"; then
    resolved="$(jq -c --arg k "$ref" '.[$k] = {state: "missing"}' <<< "$resolved")"
  else
    cat "$err" >&2; rm -f "$err"; fail "cannot read ${ref}"
  fi
  rm -f "$err"
done < <(jq -r '[.[].refs[] | "\(.repo)#\(.number)"] | unique[]' <<< "$parsed")

report="$(jq -c --arg repo "$repo" --argjson res "$resolved" '
  def key: "\(.repo)#\(.number)";
  def keys_of($state): [.deps[] | select(.state == $state) | .key] | join(", ");
  map(. as $i
    | . + {deps: [.refs[] | . + {key: key} + $res[key]]}
    | if .kind == "missing" then . + {state: "judgment", why: "no GitHub dependencies section"}
      elif .kind == "prose" then . + {state: "judgment", why: "dependency section is prose"}
      elif any(.deps[]; .repo == $repo and .number == $i.number) then . + {state: "anomalous", why: "depends on itself"}
      elif any(.deps[]; .state == "missing") then . + {state: "anomalous", why: "missing \(keys_of("missing"))"}
      elif any(.deps[]; .pr) then . + {state: "judgment", why: "references a Pull Request: \([.deps[] | select(.pr) | .key] | join(", "))"}
      elif any(.deps[]; .state == "closed" and .reason != "completed") then . + {state: "judgment", why: "closed without completion: \([.deps[] | select(.state == "closed" and .reason != "completed") | .key] | join(", "))"}
      elif any(.deps[]; .state == "open") then . + {state: "blocked", why: "waits on \(keys_of("open"))"}
      else . + {state: "ready", why: (if .deps == [] then "no dependencies" else "all delivered" end)} end)
  # Drain blocked Issues whose open same-repository dependencies are all
  # drained or outside the graph; whatever never drains is in or behind a cycle.
  | (map(select(.state == "blocked"))
     | map({key: (.number | tostring), value: [.deps[] | select(.state == "open" and .repo == $repo) | .number | tostring]})
     | from_entries) as $graph
  | ([$graph | recurse(. as $g
        | [to_entries[] | select(any(.value[]; $g[.] != null)) | .key] as $stuck
        | if ($stuck | length) == ($g | length) then empty
          else with_entries(select(.key as $k | $stuck | index($k))) end)]
     | last | keys) as $cycle
  | map(if (.number | tostring) as $n | $cycle | index($n)
        then .state = "anomalous" | .why = "in or behind a dependency cycle (\(.why))" else . end)
  # The label each state wants, applied only to Issues that already carry a
  # status label and are not in triage.
  | map(. as $i
    | ({ready: "status:ready", blocked: "status:blocked", anomalous: "status:blocked"}[.state]) as $want
    | ([.labels[] | select(. == "status:ready" or . == "status:blocked")]) as $has
    | . + {change: (
        if $want == null or ($has | length) == 0 or (.labels | index("status:triage")) then null
        else {add: ([$want] - $has), remove: ($has - [$want])}
          | if .add == [] and .remove == [] then null else . end end)})
  | sort_by(.number)
' <<< "$parsed")" || fail "cannot classify the Issues"

if [ "$apply" = true ] && jq -e 'any(.[]; .change != null)' <<< "$report" >/dev/null; then
  have="$(gh label list -R "$repo" --limit 1000 --json name --jq '[.[].name]')" || fail "cannot list labels of ${repo}"
  jq -e 'index("status:ready") and index("status:blocked")' <<< "$have" >/dev/null \
    || fail "${repo} needs both status:ready and status:blocked labels; create them or run without --apply"
  # The unit separator is not IFS whitespace, so an empty add or remove
  # field keeps its column (a tab would collapse it).
  while IFS=$'\x1f' read -r number add remove; do
    args=()
    [ -z "$add" ] || args+=(--add-label "$add")
    [ -z "$remove" ] || args+=(--remove-label "$remove")
    gh issue edit "$number" -R "$repo" "${args[@]}" >/dev/null || fail "cannot relabel #${number}"
  done < <(jq -r '.[] | select(.change) | [.number, (.change.add | join(",")), (.change.remove | join(","))] | map(tostring) | join("\u001f")' <<< "$report")
fi

if [ "$json_output" = true ]; then
  jq --arg repo "$repo" --argjson applied "$apply" \
    '{repo: $repo, applied: $applied, issues: map(del(.body, .kind, .refs))}' <<< "$report"
  exit 0
fi
jq -r --arg repo "$repo" --argjson applied "$apply" '
  "frontier \($repo): " + ([("ready", "blocked", "anomalous", "judgment") as $s | "\(map(select(.state == $s)) | length) \($s)"] | join(", ")),
  (.[] | "\(.state | . + " " * (10 - length)) #\(.number) \(.title) [\(.why)]"),
  (.[] | select(.change) | "relabel    #\(.number) +\(.change.add | join(",")) -\(.change.remove | join(",")) (\(if $applied then "applied" else "not applied; --apply" end))")
' <<< "$report"
