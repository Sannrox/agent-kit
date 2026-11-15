#!/usr/bin/env bash
# Report what each CI job of a repository costs and catches, from the run
# history GitHub keeps. Read-only: it lists runs and reads their jobs.
#
# Runs are grouped by commit across workflows, because a pull request waits
# for all of them. When a workflow ran more than once for a commit, only its
# newest run counts. One row per "workflow / job":
#   ran           times the job finished as success, failure or timed out
#   skipped       times it was skipped (it shows as a check but did nothing)
#   cancelled     times it was cancelled
#   failed        failures and timeouts
#   failed alone  commits where it was the only job that failed
#   median, p90   execution time, start to end, of the times it ran
#   queue         median wait between being queued and starting
#   last          commits where it finished last, so it set the wall time
#   runner min    execution minutes summed over the window
# Rows are sorted by runner minutes.
#
# Wall time per commit runs from the first job being queued to the last job
# finishing. It is taken only from commits with no cancelled job and no rerun:
# a cancelled commit was superseded, and a rerun keeps the original start.
# GitHub serves only the latest attempt of a run, so a failure cleared by a
# rerun is not counted; the report says how many runs were rerun.
#
# Usage:
#   bash ci-report.sh [--repo <owner/repo>] [--event <event>] [--limit <runs>] [--json]
# --event defaults to pull_request, --limit to the 300 newest completed runs.
# Exit codes: 0 reported; 1 error, including any failed GitHub read (fail
# closed: no report from a partial view). Requires an authenticated gh and jq.
set -euo pipefail

# Canonical source: Sannrox/agent-kit skills/ci-audit.

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit "${1:-2}"
}
fail() {
  printf 'ci-report: %s\n' "$1" >&2
  exit 1
}

repo=""
event="pull_request"
limit=300
json_output=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$#" -ge 2 ] || usage; repo="$2"; shift ;;
    --event) [ "$#" -ge 2 ] || usage; event="$2"; shift ;;
    --limit) [ "$#" -ge 2 ] || usage; limit="$2"; shift ;;
    --json) json_output=true ;;
    -h | --help) usage 0 ;;
    *) usage ;;
  esac
  shift
done
case "$limit" in '' | *[!0-9]* | 0) fail "--limit must be a positive integer" ;; esac
command -v gh >/dev/null || fail "gh is required"
command -v jq >/dev/null || fail "jq is required"
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || fail "cannot resolve the repository; pass --repo"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/ci-report.$$.XXXXXX")"
trap 'rm -rf "$work"' EXIT

gh run list -R "$repo" --event "$event" --status completed --limit "$limit" \
  --json databaseId,workflowName,headSha,createdAt,attempt > "$work/listed" \
  || fail "cannot list the runs of $repo"
jq 'group_by([.workflowName, .headSha]) | map(max_by(.createdAt))' "$work/listed" > "$work/runs"
[ "$(jq length "$work/runs")" -gt 0 ] || fail "$repo has no completed $event runs"

# One read per run, eight at a time, each into its own file. xargs fails when
# any read fails.
mkdir "$work/jobs"
# shellcheck disable=SC2016 # the inner shell expands $0, $1 and $2
jq -r '.[].databaseId' "$work/runs" | xargs -P 8 -I '{}' sh -c '
  gh api --paginate "repos/$0/actions/runs/$1/jobs?per_page=100" \
    --jq ".jobs[] | {run: $1, name, conclusion, created_at, started_at, completed_at}" > "$2/$1"
' "$repo" '{}' "$work/jobs" || fail "cannot read every run of $repo; no report from a partial view"

cat "$work"/jobs/* | jq -s --slurpfile runs "$work/runs" --arg repo "$repo" --arg event "$event" '
  def seconds: if . == null then null else (try fromdateiso8601 catch null) end;
  def median: sort | length as $n
    | if $n == 0 then null elif $n % 2 == 1 then .[($n - 1) / 2] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
  def p90: sort | if length == 0 then null else .[(length * 0.9 | ceil) - 1] end;

  ($runs[0] | INDEX(.databaseId | tostring)) as $run
  | map($run[.run | tostring] as $r
      | (.conclusion == "failure" or .conclusion == "timed_out") as $failed
      | {key: "\($r.workflowName) / \(.name)", workflow: $r.workflowName, job: .name,
         sha: $r.headSha, rerun: ($r.attempt > 1), conclusion, failed: $failed,
         ran: ($failed or .conclusion == "success"),
         created: (.created_at | seconds), started: (.started_at | seconds), ended: (.completed_at | seconds)})
  | . as $jobs
  | (group_by(.sha) | map(
      (map(select(.failed) | .key) | unique) as $failed
      | map(select(.ran and .ended != null)) as $ran
      | {alone: (if ($failed | length) == 1 then $failed[0] else null end),
         clean: (($ran | length) > 0 and all(.[]; .conclusion != "cancelled" and (.rerun | not))),
         ran: ($ran | length),
         last: ($ran | max_by(.ended) | .key?),
         wall: (if ($ran | length) > 0
                then ($ran | map(.ended) | max) - (map(.created | select(. != null)) | min)
                else null end)})) as $commits
  | ($commits | map(select(.clean))) as $clean
  | {repo: $repo, event: $event,
     runs: ($run | length),
     rerun_runs: ($runs[0] | map(select(.attempt > 1)) | length),
     from: ($runs[0] | map(.createdAt) | min),
     to: ($runs[0] | map(.createdAt) | max),
     commits: ($commits | length),
     clean_commits: ($clean | length),
     wall_median_s: ($clean | map(.wall) | median),
     wall_p90_s: ($clean | map(.wall) | p90),
     jobs_per_commit_median: ($clean | map(.ran) | median),
     jobs_per_commit_max: ($clean | map(.ran) | max),
     jobs: ($jobs | group_by(.key) | map(
       .[0].key as $key
       | map(select(.ran and .started != null and .ended != null) | .ended - .started) as $durations
       | {workflow: .[0].workflow, job: .[0].job,
          ran: (map(select(.ran)) | length),
          skipped: (map(select(.conclusion == "skipped")) | length),
          cancelled: (map(select(.conclusion == "cancelled")) | length),
          failed: (map(select(.failed)) | length),
          failed_alone: ($commits | map(select(.alone == $key)) | length),
          median_s: ($durations | median),
          p90_s: ($durations | p90),
          queue_median_s: (map(select(.ran and .started != null and .created != null) | .started - .created) | median),
          last: ($clean | map(select(.last == $key)) | length),
          runner_minutes: (($durations | add // 0) / 60 | round)})
       | sort_by(-.runner_minutes, .workflow, .job))}
' > "$work/report" || fail "cannot compute the report"

if "$json_output"; then
  cat "$work/report"
  exit 0
fi
jq -r '
  def minutes: if . == null then "-" else (. / 6 | round) / 10 | tostring end;
  def whole: if . == null then "-" else round | tostring end;
  "CI report for \(.repo): \(.runs) \(.event) runs, \(.commits) commits, \(.from[:10]) to \(.to[:10])",
  "Wall time per commit (\(.clean_commits) commits without a cancelled job or a rerun): median \(.wall_median_s | minutes) min, p90 \(.wall_p90_s | minutes) min",
  "Jobs that ran per commit: median \(.jobs_per_commit_median | whole), max \(.jobs_per_commit_max | whole)",
  "Runs that were rerun: \(.rerun_runs) (a failure cleared by a rerun is not counted)",
  "",
  "| Workflow / job | Ran | Skipped | Cancelled | Failed | Failed alone | Median min | p90 min | Queue s | Last | Runner min |",
  "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  (.jobs[] | "| \(.workflow) / \(.job) | \(.ran) | \(.skipped) | \(.cancelled) | \(.failed) | \(.failed_alone) | \(.median_s | minutes) | \(.p90_s | minutes) | \(.queue_median_s | whole) | \(.last) | \(.runner_minutes) |")
' "$work/report"
