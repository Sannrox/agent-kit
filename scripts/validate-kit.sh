#!/usr/bin/env bash
# Validate the canonical skills in this repository and self-test the consumer check.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
fail() { printf 'agent-kit validation failed: %s\n' "$1" >&2; exit 1; }
require_line() { grep -Fqx "$2" "$1" || fail "$1 is missing canonical line: $2"; }

for f in skills/*/SKILL.md; do
  n="$(basename "$(dirname "$f")")"
  [ "$(sed -n 1p "$f")" = "---" ] || fail "$f has no frontmatter"
  require_line "$f" "name: ${n}"
  grep -q '^description: .\+' "$f" || fail "$f has no description"
  grep -q '^# ' "$f" || fail "$f has no title heading"
done

# Shared skills stay generic: product facts belong in the consumer's AGENTS.md.
if grep -rIn -i -E '\b(kako|kekkai|mizuchi|hoshi|tenkai|rusui|mikura|aldunis)\b|shikigami GitHub|sekai-chisei (release|change|design)' \
  --exclude-dir=sekai-ontology skills; then
  fail "a shared skill names a specific product (see above)"
fi

for stage in '## Establish authority and scope' '## Build the dependency graph' '## Compute the frontier' \
  '## Apply authorized status changes' '## Report the frontier' '## Boundaries'; do
  require_line skills/advance-issue-frontier/SKILL.md "$stage"
done
for stage in '## Establish the authority ceiling' '## Deliver the Issue' '### 1. Prove readiness' \
  '### 2. Isolate the work' '### 3. Bound the implementation' '### 4. Verify and review' \
  '### 5. Publish when authorized' '### 6. Land when authorized' '## Report completion' '## Boundaries'; do
  require_line skills/deliver-ready-issue/SKILL.md "$stage"
done
for ref in references/parallel-delivery.md scripts/issue-lane.sh; do
  [ -f "skills/deliver-ready-issue/${ref}" ] || fail "missing skills/deliver-ready-issue/${ref}"
  grep -Fq "$ref" skills/deliver-ready-issue/SKILL.md || fail "deliver-ready-issue does not link ${ref}"
done
grep -Fq "issue-lane.sh check" skills/advance-issue-frontier/SKILL.md || fail "advance-issue-frontier does not use issue-lane.sh check"

for s in scripts/*.sh skills/*/scripts/*.sh; do bash -n "$s" || fail "syntax error in $s"; done

# Self-test: render a fixture consumer from the templates and check it.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.agents" "$tmp/scripts"
{ printf '# Agents\n\nShared skills: Sannrox/agent-kit.\n\n## Parallel delivery lanes\n\nissue-lane.sh claim\n\n'; cat templates/agent-skill-profile.md; } > "$tmp/AGENTS.md"
printf 'See AGENTS.md\n' > "$tmp/CLAUDE.md"; printf '/.worktrees/\n' > "$tmp/.gitignore"
bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null
touch "$tmp/.agents/project.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: leftover .agents/project.md was not detected"; fi
rm "$tmp/.agents/project.md"
printf 'drift\n' >> "$tmp/.agents/skills/verify-change/SKILL.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: drifted stub was not detected"; fi
mkdir -p "$tmp/.agents/skills/sekai-ontology" && cp skills/sekai-ontology/SKILL.md "$tmp/.agents/skills/sekai-ontology/"
cp -r skills/sekai-ontology/. "$tmp/.agents/skills/sekai-ontology/"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: vendored shared skill was not detected"; fi
bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null
printf 'agent-kit validation passed\n'
