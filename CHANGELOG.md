# Changelog

## Unreleased

### Added

- `issue-lane.sh capacity` counts live lanes against the lane limit (default
  three, `ISSUE_LANE_LIMIT`) and reports stale claim branches; `claim` refuses
  when no lane is free. `validate-kit.sh` runs its `--self-test`.

### Changed

- Breaking: no pinning. Removed `templates/agent-kit.lock`; stubs link to
  `tree/main` and read `~/.agents/agent-kit` (cloned or fast-forwarded by
  `validate-workflow-skills.sh`). Default skills and vendored scripts are
  listed in `templates/default-skills.txt` and `templates/vendored-scripts.txt`.
- Breaking: retired `.agents/project.md`. Skills read repository facts from the
  consumer's `AGENTS.md`; only content not already there goes into a
  `## Agent skill profile` section (`templates/agent-skill-profile.md`).
  `check-consumer.sh` requires that section and fails if `.agents/project.md` exists.

## v0.1.0

### Added

- Canonical shared skills, genericized from the kako, kekkai, mizuchi and hoshi
  copies (originally derived from Sannrox/shikigami@3318978): advance-issue-frontier,
  assess-change-impact, capture-project-decision, deliver-ready-issue,
  prepare-release, refactor-docs, shape-work-item, technical-documentation,
  verify-change, and the opt-in sekai-ontology.
- `.agents/project.md` convention for repository-specific facts.
- Stub template, lock file template, and `scripts/check-consumer.sh` drift check.
- Shared scripts `gh-verified-push.sh` and `validate-workflow-skills.sh`.
