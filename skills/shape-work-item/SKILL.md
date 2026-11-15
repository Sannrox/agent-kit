---
name: shape-work-item
description: Shape a raw idea, bug report, refactoring proposal, or research question into a focused GitHub Issue. Use when work needs scope, acceptance evidence, risk routing, or the correct Issue template before implementation.
---

<!-- Canonical source: Sannrox/agent-kit skills/shape-work-item. Derived from Sannrox/shikigami@331897846885e4a55697b0f1006d03b4f2a7495e. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# Shape Work Item

Turn intent into a decision-ready unit of work. Produce a draft unless the user
explicitly authorizes publishing to GitHub.

## Procedure

1. Read `AGENTS.md`, `README.md`, accepted ADRs under `docs/decisions/` when
   present, and the matching form under `.github/ISSUE_TEMPLATE/` when present.
   Inspect affected code or docs
   when named. Complete when the request is framed against actual project
   boundaries (see `## Dependencies and Ownership` in `AGENTS.md`).
2. Search open and closed Issues, Discussions, and PRs when GitHub access is
   available. Record possible duplicates or state that the search was not run.
3. Classify the work:
   - `bug`: reproducible expected-versus-actual behavior;
   - `feature`: a new observable outcome as defined by the `Feature:` line under
     `## Agent skill profile` in `AGENTS.md`;
   - `refactor`: preserved behavior with concrete structural evidence; or
   - `research`: a time-boxed question that ends in a decision.
   Route sensitive/exploitable behavior to private vulnerability reporting,
   never a public Issue. Route work owned by another repository (see `## Dependencies and Ownership` in
   `AGENTS.md`) to that repository and record it
   under `## GitHub dependencies`. Route cross-boundary,
   public-contract, trust-model, or difficult-to-reverse choices to a Design
   Discussion before implementation.
   One Issue carries one outcome that one Pull Request can deliver. When a
   review or audit yields several findings, shape one Issue per finding. Group
   findings only when they share a cause and one fix closes them all. Never
   file a list of findings as one Issue.
4. Draft with problem, observable outcome, non-goals, acceptance evidence,
   affected area (from `## Project Structure & Module Organization` in `AGENTS.md`), and
   compatibility/security risks. Omit hostnames, FQDNs, IP addresses, home
   directories, absolute worktree paths, LAN or employer network names,
   deployment or environment state, image or artifact digests, tenant or
   customer names, release-hold or rollout-hold language, or other private
   environment inventory from any text that will be published to GitHub.
   Write acceptance evidence as the observable behavior and the one boundary
   that proves it. Do not list tests: which tests exist is decided at delivery
   by the `test-audit` authoring gate.
   Say how each claim about current behavior is known: `reproduced` (you ran
   it and saw it), `read from source` (cite `path:line` at a commit), or
   `not verified`. Write `not verified` instead of a guess. A `bug` whose
   problem is `not verified` stays in `status:triage`.
   Give the body a `## GitHub dependencies` section that is exactly `none` or
   one reference per line (`- #12`, `- <owner>/<repo>#34`). It is the only
   section `advance-issue-frontier` evaluates; any other wording there leaves
   the Issue to judgment on every run. Boundaries, gates, and related work go
   in another section.
5. Settle open questions. A question left for the maintainer keeps the Issue
   in `status:triage`.
   - A fact the code, docs, or Issue history can answer: look it up.
   - A routine or reversible choice: decide it and write it into the body as
     a decision marked `Assumed:`, so review can overturn it. It does not
     block `status:ready`.
   - A choice that step 3 routes to a Design Discussion: draft the decision
     for the option you recommend (context, decision, consequences, rejected
     alternatives; the ADR form when `docs/decisions/` exists). The
     maintainer accepts or rejects a text, not a list of options.
   - Whether the outcome is wanted is the maintainer's call, and the default
     is no. When no report, request, incident, or blocked Issue shows the
     need, recommend not filing and name the evidence that would change
     that. Do not file the question.
   - The question of a `research` Issue is its outcome, not a blocker. The
     Issue is ready once the question, the time box, and the form of the
     decision are named.
6. Recommend labels (`type:*`, `area:*`, `status:ready` when no maintainer
   decision remains). Do not invent priority, assignment, or sprint.
7. Milestones are release versions. A milestone is titled with the exact
   version it ships in (for example `0.9.0`) and describes its theme in the
   milestone description, so anyone waiting on an Issue can see which release
   carries it. Never create a thematic or named milestone. Put an Issue in a
   version milestone only when the maintainer names that version; do not
   choose one.

## Output

1. route and rationale;
2. possible duplicates;
3. issue title and body ready for GitHub;
4. recommended labels;
5. maintainer decisions still blocking `status:ready`, each with its draft
   decision, or `none`.

Do not publish without explicit authorization.
