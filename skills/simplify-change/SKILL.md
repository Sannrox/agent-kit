---
name: simplify-change
description: Shrink your own change to its smallest complete fix before review. Use after implementing and before verify-change and autoreview, before opening a Pull Request, before pushing a large repair to one, or when asked to shrink a Pull Request or clean up slop.
---

<!-- Canonical source: Sannrox/agent-kit skills/simplify-change. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# Simplify Change

An editing pass by the change's author on their own branch. It precedes review
and never replaces it. Inherit the task's scope and authority: a review-only
request gets findings, not edits. The delivery workflow owns publication,
review, and merge.

**The diff is a proposal.** Passing tests show it works, not that its
architecture or every added test is needed.

Rules: the repository's `AGENTS.md` (design, compatibility and testing
sections) and the nearest scoped `AGENTS.md`. Steps 2 and 3 apply every rule
to every changed file.

## 1. Re-derive the smallest complete fix

Read the stated outcome, the complete diff against the merge base, and the
proof gathered so far. Then ask:

> Starting from the base, what is the smallest complete fix using the owners
> already present? Would I still introduce this architecture?

Inspect the largest added modules, state, adapters, and test scaffolding first.
Read their direct callers and relevant history: apparently redundant behavior
may protect a shipped configuration or an earlier regression.

Trace every changed hunk to the stated outcome. A hunk that serves another goal
leaves this change: drop it or move it to its own Pull Request.

Count the non-mechanical changed lines. Above about 800, or about 500 for
complex logic, name the smallest coherent layer that can land first and cut the
change to it (a stacked Pull Request when the repository uses stacks).

**Done when:** you can state the defect or goal, the required invariant, and
the smallest complete fix in one sentence each, and every remaining hunk serves
that fix.

## 2. Remove unnecessary architecture

- **One decision owner.** Move repeated caller-side policy into the operation
  that owns the decision. Migrate the callers and remove the old
  implementations, exports, and repair branches.
- **Existing state first.** Challenge new schemas, managers, caches, and
  combined representations. Reuse an existing owner when its lifetime,
  authority, atomicity, and cleanup fit. Keep any migration that keeps existing
  config and state working after update.
- **Delete the redundant path.** Remove parallel renderers, duplicated parsers,
  fake lifecycle calls used only to obtain a result, derived state callers can
  already obtain, and wrappers that only forward, rename, or cast. Prefer one
  simpler representation over fallback modes around the old one.
- **Polish last.** In every changed hunk keep only what a maintainer of the
  surrounding file would write:
  - comments that explain ownership, lifecycle, ordering, or constraints;
  - checks and error handling that guard real states and match the module;
  - real types instead of laundering casts (`as any`, `as unknown as T`,
    widen-then-assert, needless `clone`/`unwrap`);
  - names, helpers, and variables that add domain meaning or remove
    duplication;
  - shims, aliases, retries, and fallbacks backed by a named shipped contract
    and a removal plan.

Preserve the requested fix and supported behavior, not the proposal's
accidental design. When history (`git log -p -S <symbol>`) leaves a path's
purpose unclear, keep it and report it. Report new product decisions, breaking
contracts, and unrelated cleanup as findings for the owner instead of making
them.

## 3. Keep tests that catch failures

For each added or changed test group and its setup helpers, name the distinct
observable failure it catches.

Keep regressions for the actual defect and distinct boundaries: ordering,
cancellation, stale authority, crash and restart, takeover, rejection, real
errors. Remove same-path duplicates, mock echoes, assertions on static values,
tests that only prove removed code is gone, and test-only production hooks.
Consolidate useful cases into the existing owning suite. Removing tests never
weakens coverage of a real boundary.

**Done when:** every remaining test group has a named failure.

## 4. Prove the smaller change

Batch the edits, then rerun the reproduction and focused checks for the changed
contracts and their consumers. Reuse proof whose inputs did not change. A
preserved restart, upgrade, or wire-format claim needs proof that still
applies. `verify-change` selects the broader checks.

**Done when:** the complete diff is inspected, supported simplifications are
applied, superseded paths are unreachable, and affected behavior still has
proof. No change is a valid result when the existing shape is justified. Aim
for net-negative code, not a deletion quota.

## Report

In the Pull Request body or task handoff:

- the responsibility or machinery that disappeared;
- the behavior still protected;
- production and test line deltas against the merge base (label a reduction
  against an earlier revision separately);
- any remaining growth that is necessary, and any unresolved decision.

After later repairs, simplify only the new changes and the owners they touch.
