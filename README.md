# agent-kit

Canonical agent workflow skills and scripts for Sannrox repositories. Write a
workflow once here and reference it from every repository instead of
hand-copying long `SKILL.md` files.

## Skills

| Skill | Default | Purpose |
| --- | --- | --- |
| `advance-issue-frontier` | yes | Compute the ready Issue frontier and parallel lanes |
| `assess-change-impact` | yes | Map a change across boundaries before implementation or review |
| `capture-project-decision` | yes | Record an accepted decision in the smallest durable artifact |
| `deliver-ready-issue` | yes | Deliver a ready Issue in an isolated worktree lane (`scripts/issue-lane.sh`) |
| `prepare-release` | yes | Audit release scope, compatibility and notes |
| `refactor-docs` | yes | Restructure documentation without losing facts |
| `shape-work-item` | yes | Turn a raw idea into a focused GitHub Issue |
| `technical-documentation` | yes | Build or review technical documentation |
| `verify-change` | yes | Proportionate verification with an exact evidence report |
| `sekai-ontology` | opt-in | Sekai ontology CLI workflow, only for repos that work with the ontology |

Shared scripts: `scripts/gh-verified-push.sh` (verified commits through the
GitHub API) and `scripts/validate-workflow-skills.sh` (the consumer check).

## The stub pattern

This follows the [OpenClaw agent-skills](https://github.com/openclaw/agent-skills)
"repository entrypoint" pattern. Cursor, Claude Code and Codex discover skills
from the repository itself (`.agents/skills/<name>/SKILL.md`), so each consuming
repository keeps a short **stub** with the same name and the full description
(so the agent still selects it), whose body:

1. links the canonical skill at the pinned tag
   (`https://github.com/Sannrox/agent-kit/tree/<ref>/skills/<name>`);
2. tells the agent to read the installed copy at
   `~/.agents/agent-kit/<ref>/skills/<name>/SKILL.md` (or `$AGENT_KIT_HOME/<ref>`);
3. says how to install it when missing (`bash scripts/validate-workflow-skills.sh`
   or a `git clone --depth 1 --branch <ref>`);
4. says repository rules in `AGENTS.md` and `.agents/project.md` apply too, and
   that shared fixes go upstream here.

Stubs are generated from `templates/stub-SKILL.md`; never edit them by hand.

## Consuming repository layout

```text
AGENTS.md                      # repo policy; links Sannrox/agent-kit
CLAUDE.md                      # points to AGENTS.md
.agents/agent-kit.lock         # repo, ref (tag), commit, skills, scripts
.agents/project.md             # repo-specific facts the shared skills read
.agents/skills/<shared>/SKILL.md   # generated stubs, nothing else
.agents/skills/<local>/        # repo-only skills, full content, stay local
scripts/gh-verified-push.sh        # vendored byte-for-byte (checked)
scripts/validate-workflow-skills.sh # vendored byte-for-byte (checked)
```

Start from `templates/agent-kit.lock` and `templates/project.md`, then run
`bash scripts/validate-workflow-skills.sh --render` to write the stubs.

## `.agents/project.md` convention

Shared skills contain no product facts. Where a skill needs them it says
"see `## <Heading>` in `.agents/project.md`". The headings are a contract
(checked in CI): `Project`, `Ownership boundaries`, `Affected areas`,
`Shared surfaces`, `Impact boundaries`, `Compatibility and failure obligations`,
`Evidence map`, `Verification matrix`, `Release audit`. See `templates/project.md`.

## Versioning and drift

- Consumers pin a tag **and** its commit in `.agents/agent-kit.lock`; the check
  refuses a checkout whose HEAD differs from the pinned commit.
- `scripts/validate-workflow-skills.sh` (run in each consumer's CI) fails when a
  stub differs from the rendered template at the pin, a pinned skill does not
  exist at the pin, a shared skill is vendored or shadowed, a vendored script
  drifted, or `.agents/project.md` lacks a contract heading.
- To upgrade: change `ref` and `commit`, run `--render`, open a PR.
- Breaking changes to skill names, the stub template or project.md headings
  need a new minor version before `1.0`; record them in `CHANGELOG.md`.

## Offline and cloud agents

A stub alone does not carry the workflow. Agents need either network access to
clone the pinned tag or a pre-installed kit under `~/.agents/agent-kit/<ref>`.
Run `bash scripts/validate-workflow-skills.sh` in the environment's setup step
so the kit is installed before the agent starts.

## Development

`bash scripts/validate-kit.sh` validates the canonical skills and self-tests the
consumer check. Commits are published with `scripts/gh-verified-push.sh`.

## License

Apache-2.0
