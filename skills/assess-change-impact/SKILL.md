---
name: assess-change-impact
description: Assess a proposed or implemented change across trust, API, dependency, and operations boundaries. Use when scoping an Issue, planning tests, reviewing a diff, or identifying compatibility, documentation, and security obligations.
---

<!-- Canonical source: Sannrox/agent-kit skills/assess-change-impact. Derived from Sannrox/shikigami@331897846885e4a55697b0f1006d03b4f2a7495e. Repository-specific facts live in the consuming repository's .agents/project.md. -->

# Assess Change Impact

Build an evidence-backed impact map before implementation or review.

## Procedure

1. Read the linked Issue or request, `README.md`, accepted ADRs under
   `docs/decisions/`, and the relevant code. For a diff, inspect every changed
   file and its direct callers or implementors. Complete when the claimed
   outcome and actual change surface are both known.
2. Trace applicable boundaries:
   - every boundary listed under `## Impact boundaries` in `.agents/project.md`;
   - configuration, CLI, logs and metrics, and packaging.
   Complete when each applicable boundary has an owner and expected invariant.
3. Identify compatibility and failure obligations: version pins, partial
   failures, retries, cleanup, and every item under
   `## Compatibility and failure obligations` in `.agents/project.md`. Complete when data-loss,
   duplicate-write, and partial-failure paths are accounted for.
4. Map evidence to risk: unit tests for pure logic, plus the evidence named
   under `## Evidence map` in `.agents/project.md`; ignored live tests only when an external
   system is essential. Complete when every material risk has a proposed check
   or an explicit residual uncertainty.
5. Determine durable artifacts that must change: README, docs, examples, an
   ADR, upstream Issues in the owning repository, or a repository Skill.
   Complete when no artifact is proposed merely to record temporary planning.

## Output

Return a compact matrix with columns:

| Surface | Evidence found | Required change/check | Risk if missed |
| --- | --- | --- | --- |

Then list scope boundaries, blocking questions, and the smallest safe PR split.
Do not approve an architecture, perform a full security audit, or claim
behavior parity without inspecting the implementations.
