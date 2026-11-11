<!-- Adapted from openclaw/openclaw@9c2e60f7d003e30d417d60655a4bd2dc56168e8d .agents/skills/openclaw-testing/SKILL.md. MIT License, Copyright (c) 2026 OpenClaw Foundation; full text in this skill's LICENSE. Changes: kept the proof policy, the general CI-failure rules, the exception rule and the test failure policy; upstream's commands, remote test capacity, release and channel proof sections are omitted; links point at this skill. -->

# Proof and failure policy

## Proof policy

- **PR CI = default broad proof.** Change builds + focused tests pass → open
  ready PR. CI runs broad suites; never delay PR for pre-PR suite runs.
- **Before PR, prove narrowly:** touched tests with
  the repository's focused test command, targeted typecheck, lint, format.
  Prefer local proof for trusted, bounded work when dependencies and current
  host capacity are qualified. Local execution is optional: a focused command
  can still load a large compiler graph or expand to broad lanes.
- **Never rerun or re-push just for green.** Fix real failures; read available
  CI failure classification before attributing red.

- Prove changed contract, complete required gates, finish. Broaden/repeat only for
  changed inputs, failures, or named unresolved risk.
- Follow scoped `AGENTS.md`; authoring/reviewing tests: use
  [boundary guide](writing-tests.md#prove-behavior-at-the-owning-boundary)
  and [test-audit](../SKILL.md).

## CI failures

- Never `gh run rerun` to chase green; never local full suite for CI repair.
- Bind diagnosis to exact SHA + job. Fetch failed logs once; prefer exact run/job
  state over stale PR rollups.
- Distinguish product, harness, infrastructure, credentials, superseded-run
  cancellation. Snapshots that pass locally and fail in CI: reproduce CI's platform bytes
  before regenerating.

## Baseline and expected-failure exceptions

Narrow baseline, snapshot, ignore, and expected-failure exceptions are implementer
decisions only when each entry is verified against source and the PR records its
reason (for example, tool-owned metadata in an upgrade snapshot while user data
stays exact). Never mask a real regression or user-data change. Blanket or
unverified exceptions need approval.

## Test failure policy

- Failures = defects. Bounded reproduction attempt (same shard order first);
  identify owner; fix product, fixture, shared-state, ordering bugs.
- Proven repair: add regression; cite another owner's fix when applicable.
- Safe fix cannot be established/completed: record original failure, attempts,
  evidence, uncertainty in PR; continue under normal CI/review gates.
- Unresolved failure alone neither blocks landing nor requires extra approval.
  Passing replay ≠ proven fix.
- Never hide failures with retries, longer timeouts, weaker assertions, broader
  mocks, altered baselines.
