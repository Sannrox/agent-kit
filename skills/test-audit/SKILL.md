---
name: test-audit
description: Gate every new or changed test and audit existing ones. Use when writing, changing, reviewing or sweeping tests, to reject duplicate or implementation-coupled proof and remove test-only production seams.
---

<!-- Canonical source: Sannrox/agent-kit skills/test-audit. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->
<!-- Adapted from openclaw/openclaw@9c2e60f7d003e30d417d60655a4bd2dc56168e8d .agents/skills/test-audit/SKILL.md. MIT License, Copyright (c) 2026 OpenClaw Foundation; full text in this skill's LICENSE. Changes: the description is reworded to state when to use the skill; links to the writing guide and proof policy point at this skill's references/; the test runner is not named; one line added that sends commands to AGENTS.md. -->

# Test Audit

Test commands, runners and collision surfaces come from the consuming repository's `AGENTS.md`.

- Authoring gates every new/changed test.
- Audits: remove low-value proof in coherent owner batches; never chase deletion counts.
- Whole-subsystem campaign: read [CAMPAIGN.md](CAMPAIGN.md) first.

## Authoring gate

Before adding test, answer:

1. Protected observable behavior, invariant, or independent contract?
2. Credible regression that makes it fail?
3. Why existing proof misses it? Each contract: one primary owner at strongest
   boundary. Another layer needs distinct transport/lifecycle risk. Extend
   tables/shared fixtures; consolidate repeated setup.
4. Export, flag, wrapper, injection hook with no production caller needed?
   Move proof to real boundary instead.

- Use [boundary and cost guide](references/writing-tests.md).
- Regressions must fail pre-fix for intended reason, pass after repair; report
  unavailable baseline proof.
- One owner regression covers bug; never replay at every crossed layer.
- Behavior-preserving refactors should not break test.

## Junk patterns

- Reject self-comparisons, copied inventories, source greps,
  implementation/call-shape assertions, duplicate contracts, test-only seams,
  subject-generated expected values, mocks supplying asserted behavior.
- Fixtures must not fabricate owner receipts/order or claim persistence path
  never writes.
- Negative controls must fail at intended guard; names must match exercised behavior.
- Auditing candidates: use [full checklist](references/audit.md#junk-patterns).

## Retention bar

- Keep independent API, SDK, protocol, config, migration, storage, security,
  platform, default, prompt-byte, generated-language, package, release,
  architecture, observable-ordering contracts. Static/slow ≠ disposable.
- Source inspection must survive identifier-only refactors and guard independent
  user-facing contract.
- Baseline failures may be bugs to repair, not tests to delete.

## Audit and validation

- Before audit edit: read [candidate evidence and workflow](references/audit.md#candidate-evidence);
  inspect full owners/callers/history; record remaining proof before deletion.
- Delete obsolete production seams with tests; never optimize for deletion counts.
- Follow [proof policy](references/proof-policy.md#proof-policy); preserve active
  test-run checkouts; run owner/sibling proof + changed checks; then autoreview.
- Report causes, retained contracts, proof/cost, production versus test LOC,
  follow-ups. Commit/push/land only with task authority.
