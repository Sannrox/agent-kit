---
name: validate-behavior
description: Validate a running app, CLI, API, or generated artifact against a written behavior contract without reading source. Use after implementation to prove user-visible acceptance criteria, when a change claims a workflow works end to end, or when an agent's success report needs independent black-box proof.
---

<!-- Canonical source: Sannrox/agent-kit skills/validate-behavior. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# Validate Behavior

Judge observable behavior, not code. `verify-change` runs the deterministic
gates and `autoreview` judges the diff; this skill judges the running product
against a contract. Run it as a separate agent or session that has not seen the
implementation.

## Rules

- Read the behavior contract first. Without one, write a short one from the
  Issue acceptance criteria or the user request before testing
  ([template](references/contract-template.md)).
- Stay source-blind: no source files, diffs, tests, git history, implementation
  notes, or review output. If you cannot continue without source, stop and
  report `blocked_source_required`.
- Interact only through surfaces a user or operator has: browser, CLI, API,
  generated files, documented logs, screenshots, accessibility trees.
- Report findings against contract clauses and observable steps, never code
  locations. Aesthetic or code-quality concerns belong to code review.
- Read-only against anything live. Mutating checks run against a local or
  mock target named in the contract.

## Workspace

Keep the contract, allowed fixtures, and redacted evidence in a private temp
directory, never a fixed shared path:

```sh
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/validate-behavior.XXXXXX")"
chmod 700 "$run_dir"
cp behavior-contract.md "$run_dir/"
```

Supply credentials through environment variables or the approved secret tool;
never copy values into the workspace, report, screenshots, or logs. If the
target must start from the source checkout, start it in a separate terminal and
do not read source while validating.

## Procedure

1. Parse the contract into user tasks, expected behavior, probes, setup, and
   required evidence.
2. Prepare access: URL, command, endpoint, fixtures, artifact path.
3. Perform each user task as a real user or operator would.
4. Run anti-cheat probes: vary fixture data, refresh and retry, try empty,
   invalid, and boundary input, restart the target and check persistence,
   inspect generated output, and confirm controls do real work instead of only
   printing success.
5. Capture compact redacted evidence: terminal excerpts, response summaries,
   screenshots, file summaries.
6. Mark every relevant clause `pass`, `fail`, `blocked`, or `out_of_scope`.
   Use the [report schema](references/report-schema.md) when a machine-readable
   result is useful.
7. After a fix, rerun only the affected clauses plus nearby probes.

**Done when:** every clause has a status backed by evidence.

## Verdicts

- **fail**: behavior violates the contract, a task cannot be completed, state
  is fake or static, or evidence is too thin for a claimed pass.
- **blocked**: runtime access, credentials, fixtures, network, or tools are
  missing.
- **out_of_scope**: only when the contract excludes it or it depends on an
  open product decision.

## Report

- target exercised and the contract used;
- pass / fail / blocked / out-of-scope counts;
- each failure with reproduction steps and evidence;
- anti-cheat probes run and their results;
- remaining blockers.
