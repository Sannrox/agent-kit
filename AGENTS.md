# Repository Guidelines

This repository is the canonical source of shared agent skills and scripts for
Sannrox repositories. See `README.md` for the stub pattern and versioning.

## Project Structure & Module Organization

Canonical skills live in `skills/<name>/` (`SKILL.md`, optional `references/`,
`scripts/`, and `agents/`). Consumer stubs are generated from
`templates/stub-SKILL.md`. Default skill names and vendored scripts are listed
in `templates/default-skills.txt` and `templates/vendored-scripts.txt`.
`scripts/check-consumer.sh` is the consumer drift check;
`scripts/validate-workflow-skills.sh` is the vendored wrapper consumers run;
`scripts/gh-verified-push.sh` is the optional canonical publisher for
GitHub-signed commits. `scripts/validate-kit.sh` is this repository's gate.
Read `README.md` before changing the stub contract.

## Build, Test, and Development Commands

- `bash scripts/validate-kit.sh` validates canonical skills and self-tests the
  consumer check. It is the local gate.
- CI (`.github/workflows/ci.yml`) runs that script, then
  `shellcheck -S warning scripts/*.sh skills/*/scripts/*.sh`.

GitHub Issues are the planning source of truth. Shared skills stay in
`skills/`; this repository has no `.agents/skills/` stubs of its own. Never
commit hostnames, home paths, secrets or private environment details.

## Agent delivery closeout (required)

Green CI is **not** a substitute for structured code review. For non-trivial
implementation work (any behavior, security, settings, or public-API change)
that will be **committed, pushed, or opened as a PR**:

1. Run `bash scripts/validate-kit.sh` via the `verify-change` Skill.
2. Run **`autoreview`** before the ship commit (or before push if the commit
   already exists). **Do not vendor** the autoreview skill into this repo;
   resolve the helper from the shared skill install (first match wins):

   ```bash
   # Preferred: shared agent-skills checkout or global skills home
   if [ -x "${AUTOREVIEW:-}" ]; then :; \
   elif [ -x "$HOME/Projects/agent-skills/skills/autoreview/scripts/autoreview" ]; then
     export AUTOREVIEW="$HOME/Projects/agent-skills/skills/autoreview/scripts/autoreview"
   elif [ -x "${AGENTS_HOME:-$HOME/.agents}/skills/autoreview/scripts/autoreview" ]; then
     export AUTOREVIEW="${AGENTS_HOME:-$HOME/.agents}/skills/autoreview/scripts/autoreview"
   else
     echo "autoreview helper not found; install shared agent-skills or set AUTOREVIEW" >&2
     exit 1
   fi
   # Dirty uncommitted work:
   "$AUTOREVIEW" --mode local
   # Topic branch / open PR (preferred after commit):
   "$AUTOREVIEW" --mode branch --base origin/main
   # Already committed on a clean tree:
   "$AUTOREVIEW" --mode commit --commit HEAD
   ```

3. Treat helper output as advisory: verify each accepted finding in the real
   code, fix actionable ones, rerun tests and autoreview until the helper exits
   0 with no accepted/actionable findings (or document a maintainer judgment
   blocker in the PR).
4. Report in the PR or handoff: commands run, tests, autoreview result
   (clean / findings fixed / consciously rejected).

**Do not skip autoreview** because CI is green, the change is "small," or the
session is optimizing for throughput unless the user explicitly waived it.
Docs-only typo fixes and pure formatting may skip structured review; state the
waiver. The `deliver-ready-issue` Skill requires this same closeout before
publish/land.

Default review engine is Codex (`gpt-6.1-sol` via the helper). Read the shared
`autoreview` skill's `SKILL.md` next to the resolved helper for engines and
findings policy.

## Parallel delivery lanes

A delivery lane is one Issue, one branch, one isolated checkout, one Pull
Request, and one owner. Several agents may deliver several Issues at the same
time, on one machine or on many, only as separate lanes. One Issue is never
split across lanes, and one lane never carries a second Issue.

### Claims live on GitHub

Machines cannot see each other's worktrees, so a claim is only what GitHub
shows. An Issue is claimed, and therefore active, when any of the following
exists:

1. an open Pull Request, draft or ready, that references the Issue;
2. a branch `<type>/<issue>`, or any branch matching `*/<issue>-*`;
3. the authenticated login assigned to the Issue less than six hours ago.

An assignment older than six hours with neither branch nor Pull Request is an
ownership hint, not a veto: report it and ask the maintainer before claiming.
A claim is stale once its Issue is closed or its Pull Request has merged; its
owner or the maintainer removes it. Any other takeover first preserves the
existing branch, Pull Request, and evidence and requires the maintainer's
confirmation, unless the lead of the same parallel run owns the stalled lane.

A lane claims before it implements, under Publish or Land authority or with an
explicit claim authorization under Implement, using
`bash skills/deliver-ready-issue/scripts/issue-lane.sh claim <issue>`:

- the branch `<type>/<issue>` is created on GitHub from the default branch by
  an atomic ref creation, so when two machines race exactly one claim
  succeeds and the other sees `claimed`;
- the authenticated login is assigned to the Issue, which shows the claim in
  the Issue list and timestamps it in the Issue timeline.

`<type>` is derived deterministically so that every machine computes the same
branch: the Conventional Commit type in the Issue title, with `bug` mapped to
`fix`; otherwise the type label (`bug` → `fix`, `enhancement` → `feat`,
`documentation` → `docs`); otherwise `chore`. Lane branches carry no slug
because the name is the claim; the Pull Request title carries the description.
Human topic branches may keep `<type>/<issue>-<slug>` and are detected as
claims by the same rule, as are legacy `codex/<issue>-<slug>` branches.

An Implement-only lane cannot claim and is invisible to other machines. Say so
in the report, or ask for claim authority before starting.

### Isolation on each machine

Local isolation protects lanes that share a machine; it is not a claim.

- Each lane checks out its claim branch in `.worktrees/issue-<issue>` inside
  the repository, ignored by Git. A fresh clone dedicated to the lane, as on a
  cloud agent, is equivalent. The base SHA is recorded in the lane report.
- The primary checkout belongs to the maintainer. Agents never switch its
  branch, reset it, stash it, or run long jobs in it while another lane is
  active.
- A worktree serves exactly one Issue. Finished lanes are removed; a worktree is
  never reused for a different Issue or renamed to hide its origin.
- Shared Git state is mutated in short, serialized slots: `git fetch --prune`,
  worktree creation and removal, local branch deletion, and merging belong to
  the lead of a parallel run or happen one lane at a time on a shared machine.
  A lane commits and publishes its own branch from its own worktree; that is
  not a shared mutation. Nobody holds a slot across implementation, test runs,
  or a remote wait.

### Limits, collisions, and landing

The three-lane limit counts claims visible on GitHub per repository: open
implementation Pull Requests plus claim branches without one. Assigned or
planned work with neither is not a running lane.

Parallel lanes must not collide. Collision surfaces in this repository are
`skills/`, `templates/`, `scripts/check-consumer.sh`,
`scripts/validate-kit.sh`, `scripts/validate-workflow-skills.sh`,
`scripts/gh-verified-push.sh`, and the stub/profile contract in `README.md`.
Lanes that would both change one of these surfaces run in sequence, not in
parallel.

A lane publishes its first Verified commit to the claim branch as a draft Pull
Request that closes the Issue. Public GitHub lane fields may list only: claim
branch, repo-relative worktree (for example `.worktrees/issue-N` — never an
absolute path), base SHA, and published SHA. Keep absolute paths and
machine/host names in the private agent session only. Never put hostnames,
FQDNs, home directories, LAN or employer network names, or other private
environment inventory on the Pull Request. It marks the Pull Request ready
when verification and review are complete. Immediately before publishing, the
lane fetches and confirms that the default branch is an ancestor of its head;
it refreshes onto `main` only for a conflict, a failing gate, an explicit
request, or a sibling landing on a shared surface, not merely because `main`
advanced.

Landing is sequential. After each merge, fetch, recompute the frontier, and let
the remaining lanes recheck `mergeable` against the new `main`. A failed or
timed-out merge response may still have merged; reconcile the remote state
before retrying.

The lead of a parallel run keeps a ledger per lane: Issue, branch, base SHA,
owner, state, Pull Request, evidence, blockers, and cleanup. Keep hostnames
and absolute checkout paths in the session with the maintainer, never on
GitHub. Report verified outcomes, not launched work. The executable lead
procedure is `skills/deliver-ready-issue/references/parallel-delivery.md`.

## Rules

- Shared skills stay generic. Never name a specific product in `skills/`
  (except the opt-in `sekai-ontology`); put product facts behind a
  reference to the consumer's `AGENTS.md` (`## Agent skill profile` or an
  existing section) instead.
- A new `## Agent skill profile` heading, a renamed skill, or a stub template change
  is a contract change: update `templates/`, `scripts/check-consumer.sh`,
  `README.md` together. Release notes belong in the pull request body;
  [CHANGELOG.md](CHANGELOG.md) is release-owned.
- Validate before handoff: `bash scripts/validate-kit.sh`.
- Publish with `bash scripts/gh-verified-push.sh` so commits are Verified. Do not
  push local commit objects directly.
- Consumers always use `main`; there is no pinning. Changes to the stub
  template, vendored scripts, skill names or profile headings break consumer
  CI until they re-render, so ship them with the consumer re-render PRs.
  Tags are optional history only.

## Coding Style & Naming Conventions

Keep skills directive and generic. Frontmatter `name` matches the directory.
Shell scripts are `bash` with `set -euo pipefail`. Prefer exact commands and
repo-relative paths over wrappers. Fail closed on missing kit files, drifted
stubs, and leftover `.agents/project.md`.

## Testing Guidelines

Add focused checks in `scripts/validate-kit.sh` for changes touching skill
frontmatter, required headings, the stub template, vendored scripts, or the
consumer check. Prefer deterministic fixture renders that do not need GitHub.
`bash scripts/validate-kit.sh` must stay green offline.

## Commit & Pull Request Guidelines

Use short imperative subjects, often Conventional Commit style:
`feat: read repository facts from AGENTS.md`,
`docs: document the stub pattern`,
`fix: refuse a vendored shared skill`. Keep commits
narrow and describe the affected surface when useful. Pull requests should
include a concise behavior summary, **tests run**, **autoreview result** (for
non-trivial code), linked issue or context, and any configuration or security
implications. Do not put hostnames, FQDNs, home directories, absolute worktree
paths, LAN or employer network names, or other private environment inventory on
public Issues, Pull Requests, comments, or commit messages. Release notes
belong in the pull request body; [CHANGELOG.md](CHANGELOG.md) is release-owned.

### Verified commits on GitHub

Prefer publishing PR branch tips with signed commits so GitHub shows
**Verified**:

1. Implement and commit locally as usual (`commit.gpgsign` may still apply).
2. Publish the claim branch with `scripts/gh-verified-push.sh` instead of a
   plain `git push` when you want the hosted commit Verified:
   - New branch:
     `scripts/gh-verified-push.sh --create-branch-from origin/main --branch <topic> --sync-local`
   - Existing PR branch:
     `scripts/gh-verified-push.sh --branch <topic> --sync-local`
3. Never pass `--no-gpg-sign` for local commits; if GPG fails, stop and fix it.

When merging PRs, prefer **squash** (`gh pr merge --squash --delete-branch`) so
the land commit on `main` is also GitHub-signed/Verified and history stays
linear. Use `gh pr merge --merge` only when multi-commit history must be kept
(original SHAs preserved). Avoid GitHub **rebase** merges when Verified history
matters: rebase-merge rewrites commits and drops signatures. Do not rewrite
protected `main` after merging unless the user explicitly approves; if
protection is temporarily relaxed, restore force-push and status-check settings
immediately after the correction.

## Security & Configuration Tips

Never commit secrets, tokens, provider credentials, logs, or local state.
Never put hostnames, FQDNs, home directories, absolute worktree paths, LAN or
employer network names, or other private environment inventory on public
Issues, Pull Requests, comments, or commit messages. Report suspected bypasses
privately (GitHub private vulnerability reporting or the maintainer), never in
a public Issue.

## Agent skill profile

Repository facts the shared agent-kit skills read. Only content not already in
the sections above belongs here.

Feature: a shared workflow skill, stub contract, or consumer check.

### Compatibility and failure obligations

Consumers track `main`. A stub-template, vendored-script, skill-name, or
`## Agent skill profile` heading change breaks consumer CI until they
re-render. Shared skills stay generic.

### Verification matrix

Rows beyond `## Testing Guidelines`:

| Surface | Required evidence |
| --- | --- |
| skill contract | `bash scripts/validate-kit.sh` |
| shell scripts | `shellcheck -S warning scripts/*.sh skills/*/scripts/*.sh` |

### Release audit

- CHANGELOG Unreleased versus tagged history;
- stub template and vendored-script contract;
- consumer re-render PRs for breaking kit changes.
