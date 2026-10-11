# Repository Guidelines

This repository is the canonical source of shared agent skills and scripts for
Sannrox repositories. See `README.md` for the stub pattern and versioning.

## Rules

- Shared skills stay generic. Never name a specific product in `skills/`
  (except the opt-in `sekai-ontology`); put product facts behind a
  `.agents/project.md` heading reference instead.
- A new `.agents/project.md` heading, a renamed skill, or a stub template change
  is a contract change: update `templates/`, `scripts/check-consumer.sh`,
  `README.md` and `CHANGELOG.md` together.
- Validate before handoff: `bash scripts/validate-kit.sh`.
- Publish with `bash scripts/gh-verified-push.sh` so commits are Verified. Do not
  push local commit objects directly.
- Consumers always use `main`; there is no pinning. Changes to the stub
  template, vendored scripts, skill names or project.md headings break consumer
  CI until they re-render, so ship them with the consumer re-render PRs.
  Tags are optional history only.
