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

1. links the canonical skill on `main`
   (`https://github.com/Sannrox/agent-kit/tree/main/skills/<name>`);
2. tells the agent to read the installed copy at
   `~/.agents/agent-kit/skills/<name>/SKILL.md` (or `$AGENT_KIT_HOME`);
3. says how to install or update it (`bash scripts/validate-workflow-skills.sh`,
   or `git clone` / `git pull` of this repository);
4. says repository rules in `AGENTS.md` and `.agents/project.md` apply too, and
   that shared fixes go upstream here.

Stubs are generated from `templates/stub-SKILL.md`; never edit them by hand.

## Consuming repository layout

```text
AGENTS.md                      # repo policy; links Sannrox/agent-kit
CLAUDE.md                      # points to AGENTS.md
.agents/project.md             # repo-specific facts the shared skills read
.agents/skills/<shared>/SKILL.md   # generated stubs, nothing else
.agents/skills/<local>/        # repo-only skills, full content, stay local
scripts/gh-verified-push.sh        # vendored byte-for-byte (checked)
scripts/validate-workflow-skills.sh # vendored byte-for-byte (checked)
```

Start from `templates/project.md`, then run
`bash scripts/validate-workflow-skills.sh --render` to write the stubs.

## `.agents/project.md` convention

Shared skills contain no product facts. Where a skill needs them it says
"see `## <Heading>` in `.agents/project.md`". The headings are a contract
(checked in CI): `Project`, `Ownership boundaries`, `Affected areas`,
`Shared surfaces`, `Impact boundaries`, `Compatibility and failure obligations`,
`Evidence map`, `Verification matrix`, `Release audit`. See `templates/project.md`.

## Versioning and drift

There is no pinning, exactly like OpenClaw: consumers always use the latest
`main`. Tags may exist for history, but nothing references them.

- `scripts/validate-workflow-skills.sh` (run in each consumer's CI) clones or
  fast-forwards `~/.agents/agent-kit` to `main`, then fails when a default
  skill (`templates/default-skills.txt`) has no stub, a stub differs from the
  current template, a stub names a skill that no longer exists, a shared skill
  is vendored, a vendored script (`templates/vendored-scripts.txt`) drifted, or
  `.agents/project.md` / `AGENTS.md` lacks a required heading.
- Because consumers track `main`, a change here to the stub template, the
  vendored scripts, skill names or project.md headings turns consumer CI red
  until they re-run `--render`. Treat those as breaking: announce them in
  `CHANGELOG.md` and open the re-render PRs together with the change.
- Opt-in skills (`sekai-ontology`) are added by creating
  `.agents/skills/<name>/` and running `--render`.

## Offline and cloud agents

A stub alone does not carry the workflow. Agents need either network access to
clone `main` or a pre-installed kit under `~/.agents/agent-kit`.
Run `bash scripts/validate-workflow-skills.sh` in the environment's setup step
so the kit is installed and current before the agent starts.

## Development

`bash scripts/validate-kit.sh` validates the canonical skills and self-tests the
consumer check. Commits are published with `scripts/gh-verified-push.sh`.

## License

Apache-2.0
