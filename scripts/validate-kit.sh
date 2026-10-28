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
grep -Eq 'issue-lane\.sh"?[[:space:]]+check' skills/advance-issue-frontier/SKILL.md || fail "advance-issue-frontier does not use issue-lane.sh check"

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

# Self-test: gh-verified-push.sh warns once per pushed file that becomes
# 100755 (added, or changed from 100644), and not for a modified file that
# already was. A dry run with --repo and --expected-oid never touches the
# network; a failing gh stub proves it.
push="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-push.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$push"' EXIT
mkdir -p "$push/bin" "$push/repo"
printf '#!/bin/sh\necho "gh must not be called" >&2\nexit 1\n' > "$push/bin/gh"; chmod +x "$push/bin/gh"
g() { git -C "$push/repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q
printf 'a\n' > "$push/repo/plain.sh"; printf 'b\n' > "$push/repo/old-exec.sh"
g add . && g update-index --chmod=+x old-exec.sh && g commit -qm base
base="$(g rev-parse HEAD)"
printf 'c\n' > "$push/repo/new-exec.sh"; printf 'a2\n' > "$push/repo/plain.sh"; printf 'b2\n' > "$push/repo/old-exec.sh"
g add plain.sh new-exec.sh old-exec.sh && g update-index --chmod=+x new-exec.sh plain.sh old-exec.sh && g commit -qm head
[ "$(g ls-tree HEAD old-exec.sh | cut -d' ' -f1)" = 100755 ] || fail "self-test: fixture should keep old-exec.sh 100755"
out="$(cd "$push/repo" && PATH="$push/bin:$PATH" bash "$ROOT/scripts/gh-verified-push.sh" \
  --repo o/r --branch b --expected-oid "$base" --dry-run 2>&1)" || fail "self-test: gh-verified-push dry run failed: $out"
printf '%s\n' "$out" | grep -q 'files changed: 3$' || fail "self-test: fixture should push three files: $out"
[ "$(printf '%s\n' "$out" | grep -c '^Warning: ')" = 2 ] || fail "self-test: expected two mode warnings, got: $out"
printf '%s\n' "$out" | grep -q '^Warning: new-exec.sh is 100755' || fail "self-test: no warning for added new-exec.sh: $out"
printf '%s\n' "$out" | grep -q '^Warning: plain.sh is 100755' || fail "self-test: no warning for plain.sh made 100755: $out"
if printf '%s\n' "$out" | grep -q '^Warning: old-exec.sh'; then fail "self-test: modified old-exec.sh keeps 100755 and needs no warning: $out"; fi
printf 'agent-kit validation passed\n'
