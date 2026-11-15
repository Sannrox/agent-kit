---
name: ci-audit
description: Audit a repository's CI from its run history and gate every new or changed CI job. Use when CI is slow, when the check list on a Pull Request keeps growing, when asked which jobs earn a place on Pull Requests, or when adding or changing a job or trigger in `.github/workflows/`. Measure first, judge a job by what it alone catches, move before deleting.
---

<!-- Canonical source: Sannrox/agent-kit skills/ci-audit. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# CI Audit

A CI job is proof with a recurring price: runner minutes, wall time on every
Pull Request, and one more row to read. Judge it by the failures only it
catches, not by its name or age.

## When it runs

- **Admission gate:** in every change that adds a job or widens a trigger.
- **Audit:** on request, when CI feels slow or the check list has grown.
- **Recheck:** once after an audit's changes land, on the same window size.

It never runs on a schedule and is never a CI job itself.

## Admission gate

Before adding a job or widening a trigger, answer in the Pull Request:

1. Which failure does it catch that no existing job catches? One owner per
   contract, as in `test-audit`. No answer: no job.
2. Can it be a step in an existing job? A new job pays checkout, toolchain and
   cache setup again.
3. Which trigger is the latest that still catches the failure before it ships:
   Pull Request, default-branch push, schedule, or release? A Pull Request job
   needs a failure that Pull Request diffs cause and that is costly to find
   later.
4. Which paths can break it? Scope the trigger to them.
5. Does it become the longest job on a Pull Request? Then it sets the wall
   time for everyone; say so and justify it.

## Audit

Discovery is read-only. Workflow edits go through the repository's delivery
workflow.

### 1. Measure

```bash
bash "${AGENT_KIT_HOME:-$HOME/.agents/agent-kit}/skills/ci-audit/scripts/ci-report.sh"
```

It reads the 300 newest completed Pull Request runs of the current repository
(`--repo`, `--event`, `--limit`, `--json`; the script header defines every
column). Use a window of at least a week of normal work, and state it.

### 2. Read each row

- **Last** names the job that sets the wall time. Speed work on any other job
  changes cost, not waiting.
- **Queue** high everywhere is a runner shortage; no job change fixes it.
- **Skipped every time:** its workflow triggers on an event where the job never
  runs. It costs no minutes but adds a check row. Narrow the trigger or split
  the workflow.
- **Failed alone** above zero: it catches what nothing else does. Keep it where
  it is unless it is the wall time.
- **Failed, never alone, always beside the same job:** possible duplicate proof.
  Read both jobs before deciding.
- **Fails often for reasons outside the diff** (advisory feeds, external
  services, flakes): not a Pull Request gate. Make it non-blocking there and
  strict on a schedule, or repair the flake at its owner.
- **Zero failures is not a verdict.** Before judging, check: does the job
  report through another channel (alerts, comments, artifacts)? Does it guard
  a rare, costly break (release, migration, security, compatibility)? Does
  history show it was added on purpose? Is the window too short?

### 3. Decide, in this order

1. **Keep** what fails alone and is cheap.
2. **Scope** by path what only some changes can break.
3. **Move** to a later trigger what Pull Request diffs rarely break. A moved
   job still catches the failure, only later.
4. **Merge** into another job what shares its setup or its proof.
5. **Speed up** the job that sets the wall time, with `improve-performance`.
6. **Delete** only when another job owns the proof. Name that job.

Never chase a job count. Before moving, renaming or deleting a job, read the
default branch's required checks: a required check that stops reporting blocks
every Pull Request. Where moves would keep touching branch protection, make
one aggregate job the only required check; it `needs` every Pull Request job
and fails on any failure or cancellation.

### 4. Report

Window, wall time (median and p90), the table, and one decision per job with
its evidence. After the changes land, rerun the script and report the new
wall time beside the old. Keep a private repository's report out of public
Issues and Pull Requests.
