<!-- Adapted from openclaw/openclaw@9c2e60f7d003e30d417d60655a4bd2dc56168e8d docs/help/testing/writing-tests.md. MIT License, Copyright (c) 2026 OpenClaw Foundation; full text in this skill's LICENSE. Changes: kept the boundary, cost, flake and regression sections; links point at this skill; upstream's test command, port helper and fixture names are replaced by neutral wording; the test-line allocation record, planner job budgets and fixture recipes specific to upstream are omitted. -->

# Writing and adding tests

## Prove behavior at the owning boundary

Prove a caller-visible contract through its production owner with fixed external
I/O fixtures and independent expected values. Prefer focused integration tests
and independent unit contracts over mocked internal decisions or whole-product
boots. Name the credible regression and what the test cannot prove.

Work in vertical slices: failing behavior, coherent repair, passing proof.
Regressions must fail on the original defect, not fixture setup; report unavailable
baseline proof. Refactor under green tests and preserve distinct contracts when
consolidating coverage. Use synthetic content and keep credentials out of captures.

Apply the [test value gate](../SKILL.md#authoring-gate)
and [proof policy](proof-policy.md#proof-policy).
Too many private controls suggest fragmented ownership,
not a need for test-only exports.

## Cost budget

Measure every new or changed test file with the repository's focused
single-file test command on one worker; report wall time and CI seconds once
available; PRs state both.

- Seconds-long tests must prove a contract no cheaper layer can. Long end-to-end
  compositions belong in the release-only tier.
- Target under 5 seconds of test time per file. Above 30 seconds, explain the
  contract and why no cheaper layer proves it.
- Inject clocks; do not add real timers, sleeps, or polling. Claim free ports
  (bind port 0), isolate each file's state, and reuse suite-level
  service/process fixtures; never boot one per test when a suite-level fixture
  exists. Import narrow APIs, not broad barrels. Fix shared state; do not add
  serial configs or worker pins.
- Async E2E waits: produced state, never action return.

## Flake triage

Follow the canonical
[test failure policy](proof-policy.md#test-failure-policy).
Reproduce the original shard order before running alone; order-only failures
usually mean earlier-file shared-state leaks. Classify fixture state, missing
completion signals, and product races. Repair the producer. If a removal caused
the red, read its PR's accepted tradeoffs before restoring it. Choose repeat
counts for the reproduced failure mode, not a fixed clean-run quota.

## Adding regressions (guidance)

Pass bounded synthetic inventories and fixed timing through real planners for
capacity bugs. Preserve coverage, ownership, and execution-budget assertions;
keep real-checkout inventory coverage in its existing integration tests.

For live provider bugs, prefer a CI-safe regression at the smallest production
composition reaching the defect: real adapters with captured requests, service
integration for session/history/tool pipelines, or independent parser unit
contracts. Keep inherently live-only checks narrow and opt-in.
