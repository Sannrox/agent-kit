---
name: prepare-release
description: Prepare a release by auditing version scope, compatibility, validation, artifacts, and release notes. Use when a maintainer asks for release readiness, a version bump plan, or a draft GitHub Release.
---

<!-- Canonical source: Sannrox/agent-kit skills/prepare-release. Derived from Sannrox/shikigami@331897846885e4a55697b0f1006d03b4f2a7495e. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# Prepare Release

Assemble decision-ready release evidence and, when authorized, carry the
release through to a verified published version. The repository's release
procedure (linked from `AGENTS.md`, often `RELEASING.md`) owns the tag
scheme, the release workflow, and retry rules; this Skill follows it.
The newest release always comes from `main`. A matching maintenance line
ships only patches for a pinned line older than the newest final release
([references/maintenance-lines.md](references/maintenance-lines.md)).

## Establish the authority ceiling

Infer the ceiling from the user's explicit request. When it is unclear, choose
the lower ceiling and state what remains:

- **Prepare**: audit, draft notes and `CHANGELOG.md` locally, report go/no-go.
- **Publish**: prepare, then open the version-bump Pull Request.
- **Release**: publish, land the version bump, hand the maintainer the tag,
  then watch and verify the published release and close its milestone.

Permission for a higher stage includes its preceding stages. "Prepare" or
"check readiness" never authorizes a Pull Request. No ceiling authorizes an
agent to create, sign, push, move, or delete a release tag, or to edit a
published release.

## Prepare the release

1. Identify the target version, base tag, target commit, merged PR range, and
   the milestone titled with the target version (milestones are release
   versions; see `shape-work-item`). A patch on a line older than the newest
   final release follows
   [references/maintenance-lines.md](references/maintenance-lines.md): the
   base is that `release-<line>` branch, not `main`. A fix for the newest
   line releases from `main`, as the next minor when `main` has breaking
   changes since the last tag; never open a `release-*` line for it. Read the version
   source named in `AGENTS.md`, CI, and open release-blocking Issues. Every
   open Issue in the version milestone is either closed by this release or
   moved to a later version milestone by the maintainer; list each one as
   closed, moved, or blocking. Complete when the exact release contents are
   bounded.
2. Classify changes as `Added`, `Changed`, `Fixed`, `Security`, or `Migration`.
   Check SemVer fit; before `1.0`, call out all public breaking changes even when
   they fit a minor bump. Complete when every user-visible merged change is
   represented once.
3. Audit release impact:
   - version and lockfile consistency when the repository has them;
   - every item under `### Release audit` under `## Agent skill profile` in `AGENTS.md`;
   - configuration additions, removals, and defaults;
   - packaging, rollback, and upgrade actions.
   Complete when every applicable item is resolved or a named blocker.
4. Use `verify-change` for the full local gates. Confirm current GitHub CI and
   security checks when access is available; when CI cannot run, say so and
   rely on recorded local evidence for the target commit. Complete when
   evidence is current for the target commit.
5. Draft concise user-facing release notes and update `CHANGELOG.md`. Put upgrade and consumer actions before internal
   implementation detail. Release notes describe versions and behavior, never
   hostnames, FQDNs, IP addresses, home directories, absolute worktree paths,
   LAN or employer network names, deployment or environment state, image or
   artifact digests, tenant or customer names, release-hold or rollout-hold
   language, or other private environment inventory.
6. Report go/no-go. A release is `go` only when required checks pass, no known
   blocker remains, and rollback/upgrade implications are explicit. Stop here
   under Prepare, or on `no-go` under any ceiling.

## Publish the version bump

The steps are the same on `main` and on a maintenance line. The base is
`origin/main`, or `origin/release-<line>` when this release is for that
line. The worktree, bump branch, and squash-merge target follow the base.

1. Work in a dedicated worktree, `.worktrees/release-<version>` on branch
   `release/<version>` from that base. Never switch, reset, or clean the
   primary checkout.
2. Commit the version source, lockfiles, and the new `CHANGELOG.md` version
   section together; nothing else. A pre-release (`-rc.N`, `-beta.N`) gets its
   own section; the final version never reuses pre-release notes.
3. Publish with the path `AGENTS.md` names (for example
   `gh-verified-push.sh --create-branch-from origin/main` or
   `--create-branch-from origin/release-<line>`), otherwise
   `git push`. Open the Pull Request against that same base, with the
   release-note draft and the milestone list in its body, and mark it ready
   once its checks pass. Return the Pull Request URL. Stop here under Publish.

## Establish the release

1. Land the version bump once its checks pass and the go verdict still holds:
   `gh pr merge <pr> --squash --delete-branch --match-head-commit <sha>`.
   Never queue GitHub auto-merge. A failed or timed-out merge response may
   still have merged; reconcile the Pull Request state before retrying.
   Record the merge commit on `main` or on the matching `release-<line>`
   branch; it is the release commit. Remove the release worktree.
2. Hand the maintainer the exact tag command for the release commit, in the
   form the release procedure requires, for example:

   ```sh
   git fetch origin && git tag -s v<version> -m "v<version>" <merge-sha> && git push origin v<version>
   ```

   Stop and wait for the maintainer to report the tag pushed. Do not poll.
3. Verify the tag before trusting the release: it exists on GitHub, is
   annotated, points at the release commit, and is signed when the procedure
   requires it (`gh api repos/<owner>/<repo>/git/tags/<tag-object-sha> --jq
   .verification.verified`). A wrong tag is a blocker for the maintainer;
   never move, delete, or reuse it.
4. Watch the release workflow the procedure names
   (`gh run list --workflow <file> --limit 5`, then
   `gh run watch <run> --exit-status`). On failure, follow the procedure's
   retry rules: a workflow fix lands on `main` and reruns the same tag; a
   defect in the tagged content needs a new pre-release or patch version.
   When the repository has no release workflow, draft the GitHub Release with
   `gh release create <tag> --verify-tag --draft --notes-file <section>` from
   the matching `CHANGELOG.md` section and leave publishing to the maintainer.
5. Verify the published release with
   `gh release view <tag> --json tagName,isDraft,isPrerelease,body,assets`:
   not a draft, pre-release exactly when the version has a pre-release suffix,
   body equal to the `CHANGELOG.md` section, and the artifacts the
   `### Release audit` requires attached. A final release of the current
   line is the repository's latest release. A final release on a previous
   maintenance line is not latest. A pre-release never is.
6. After a final release, close the version milestone when no open Issues
   remain in it. A pre-release leaves the milestone open.

## Output

Return the ceiling reached, target, commit range, the version milestone's
Issues (closed, moved, or blocking), readiness checklist, validation results,
compatibility notes, release-note draft, and blockers. Under Publish or
Release add the Pull Request and release commit; under Release add the tag,
workflow run, release URL, verification results, and milestone state.
Separate verified facts from recommendations.

## Boundaries

- Never create, sign, push, move, or delete a release tag; the maintainer
  does.
- Never edit, re-publish, or delete a published release; cut a new version.
- Release only from a commit on `main` or the matching maintenance line.
- Never cut the newest release from a maintenance line.
- Change `CHANGELOG.md` only in the version-bump Pull Request.
