---
name: improve-performance
description: Make a slow or heavy flow faster with measured proof. Use for latency, CPU, memory, SQL, RPC, or render problems, when writing or reviewing a performance Pull Request, or before adding a cache. Count the work, delete waste first, cache last.
---

<!-- Canonical source: Sannrox/agent-kit skills/improve-performance. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# Improve Performance

**Waste** is work a request does not need. Big wins come from deleting waste,
not from doing the same work faster. A cache is the last resort: it hides
waste until its key, invalidation, or hit rate breaks, and the waste returns.

For how code lowers onto the machine (layout, locality, contention), use
`mechanical-sympathy` once this skill has found the hot path.

## 1. Measure

Write the acceptance rule in the Pull Request **before** the first run: flow,
workload, metric, cold or warm, sample count, and what counts as a win or a
regression.

- **Counts first.** Operations per action (SQL statements, RPCs, frames, file
  reads, registry loads, process spawns, renders, allocations) before wall
  time. Counts hold steady on a loaded host. A count that should be zero is the
  bug.
- **Real flow.** The build under test, real transport, the slow path included.
  A mock server, stale build, or dev server measures something else.
- **Samples.** Baseline and candidate interleaved (ABAB), at least 5 each, cold
  and warm kept apart. Report median and p95 with spread, run serially, and
  record host load.
- **Rerunnable.** Only committed benchmark scripts or benches count. Extend an
  existing one when none fits.
- **Profile** the hot path (CPU profile, flamegraph, browser trace).

**Done when:** the flow has a committed workload, a baseline table, and a
written rule.

## 2. Find waste

Ask of every counted operation: does this request need it? Recurring shapes:

- eager work on the critical path (loading optional subsystems at startup);
- per-row or per-call recompute of something that changes rarely;
- re-checking state that was already admitted or validated;
- a full rescan per streamed delta;
- re-reading your own write;
- rebuilding a catalog or registry per call, miss, or TTL;
- waiting on optional data before showing required data;
- defensive deep copies and per-value boundary wrapping;
- a process spawn or fan-out per call;
- render cascades and resending full payloads for one delta.

**Done when:** each dominant count traces to the code that issues it, with a
yes or no on "needed".

## 3. Fix in this order

1. **Delete** the waste. A failed delete removed a guard, so keep every check
   that protects a contract and prove the contract still holds.
2. **Once at the owner:** callers consume the owner's recorded fact.
3. **Carry the prepared fact** through the hot path.
4. **Batch** independent work, and prove the batch keeps latency tails, frames,
   and cold start steady. Coalescing often regresses tails.
5. **Cache**, with a written reason why steps 1 to 4 do not apply. Key on the
   full identity of the inputs, invalidate from the owner's writes, bound the
   size, and add an interleaved work-count test. Most cache bugs are silent
   misses: readers evicting each other or a budget that thrashes.

Moving work to a worker or deferring it relocates cost: count main-thread and
total work both.

**Done when:** the waste is gone from the counts, or the Pull Request says
which step stopped and why.

## 4. Land

- Rerun the step 1 workload on baseline and candidate under the same rule.
- Every user-facing metric holds or improves: latency, p95/p99, cold start,
  CPU, memory, counts. A worse metric needs the owner's explicit acceptance. A
  20% move in one cell is a stop, never "within spread".
- Revert changes without a measurable gain.
- Proof lives in the Pull Request, not in new tests. Add a work-count test only
  when this waste has come back before.

Pull Request evidence: workload command, acceptance rule, before/after table
(counts and times, median and p95, samples), waste removed, and any metric that
moved the wrong way.

**Done when:** the table meets the rule written in step 1.
