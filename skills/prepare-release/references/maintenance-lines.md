<!-- Canonical source: Sannrox/agent-kit skills/prepare-release. Derived from Sannrox/shikigami@331897846885e4a55697b0f1006d03b4f2a7495e. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# Maintenance lines

Use this procedure only when a component that something else pins needs a
fix on a line older than `main`. That covers a library consumed by tag, and
a server or product others deploy by version. A server only its owner
deploys, continuously, fixes forward on `main` and gets no maintenance line.

This is not a second trunk and not a separate skill. `prepare-release`
follows it; `deliver-ready-issue` names the backport after the `main` pull
request lands.

## Branch

Name the line `release-<major>.<minor>`, one per minor, before and after
1.0: `v2.0.3` releases from `release-2.0`, `v2.1.0` from `release-2.1`.
Create it from the last tag of that line when the first fix needs it,
never in advance. The hyphen keeps the line apart from the
`release/<version>` bump branches this skill already uses: a `release-*`
protection rule or CI trigger does not match them.

## Eligible changes

Only critical bug fixes (data loss, corruption, panic, crash, hang),
security fixes, and prerequisites for a required dependency update. A fix
that only matters behind an off-by-default experimental feature does not
qualify.

## Fixes

1. **Upstream first.** Land the fix on `main`, then open one pull request
   per supported line, newest to oldest, built with `git cherry-pick -x` so
   the trailer records the source commit. A rewrite for the older code says
   so in the pull request. A fix that does not apply to `main` at all states
   why. A skipped line is explained on the source pull request.
2. **Urgent exception.** A fix may land on the line first. Commit it there
   and give its forward-port pull request to `main` an owner in the release
   record before the tag. The release does not close with the forward-port
   untracked.
3. **Record every backport.** The release notes or pull request name the
   source and destination commit of every backport and any adaptation. After
   a candidate is cut, only fixes for confirmed release blockers go in: no
   opportunistic backports and no rebasing onto newer `main`.

The `main` delivery stays one lane. The backport is a follow-up on the
line, not a second `deliver-ready-issue` lane, and not an
`issue-lane.sh land` onto a non-default base.

## Supported lines

The current line plus at most one previous line. An older line retires
unless the maintainer decides otherwise.

## Tags

The maintainer still cuts the tag (signed and annotated) on the release
commit, which is on `main` or on the matching `release-*` branch. A GitHub
Release on a previous line is never marked latest; latest stays on the
current line.

## Version bump

The version-bump steps in `prepare-release` are unchanged. Only the base
changes: the worktree `.worktrees/release-<version>`, the bump branch
`release/<version>`, and the squash-merge target use `release-<line>`
instead of `main`.

## Tooling contract for adopting repositories

- CI runs on pushes to `release-*`.
- Release workflows accept a tag reachable from `main` or from the
  `release-*` branch that matches the tag's version.
- A GitHub Release on a previous line is never marked latest.
- `release-*` gets the same protection as `main`.
