#!/usr/bin/env bash
# Check (or render) a consuming repository against a pinned agent-kit checkout.
#
# Usage: check-consumer.sh <kit-dir> <repo-root> [--render]
#
# Checks:
#   - every skill in .agents/agent-kit.lock exists in the kit and its stub in
#     .agents/skills/<name>/ is exactly the rendered templates/stub-SKILL.md
#     (only SKILL.md, no vendored references or scripts);
#   - no other .agents/skills/<name> shadows a kit skill (no vendored copies);
#   - vendored scripts listed under scripts= are byte-identical to the kit;
#   - .agents/project.md has every contract heading;
#   - AGENTS.md references Sannrox/agent-kit and keeps the parallel-lane policy;
#     CLAUDE.md points to AGENTS.md; .gitignore ignores /.worktrees/.
# --render rewrites the stubs and vendored scripts from the kit, then checks.
set -euo pipefail

kit="${1:?kit dir}"; root="${2:?repo root}"; mode="${3:-check}"
lock="${root}/.agents/agent-kit.lock"
errors=0
fail() { printf 'agent-kit check: %s\n' "$1" >&2; errors=$((errors + 1)); }

[ -f "$lock" ] || { fail "missing .agents/agent-kit.lock"; exit 1; }
field() { sed -n "s/^$1=//p" "$lock" | head -n 1; }
ref="$(field ref)"; skills="$(field skills)"; scripts="$(field scripts)"
[ -n "$ref" ] || fail "lock has no ref"
[ "$(field repo)" = "Sannrox/agent-kit" ] || fail "lock repo must be Sannrox/agent-kit"

render() { # render <skill>
  local name="$1" canon="${kit}/skills/$1/SKILL.md" desc title
  desc="$(sed -n '2,/^---$/s/^description: //p' "$canon" | head -n 1)"
  title="$(sed -n 's/^# //p' "$canon" | head -n 1)"
  awk -v n="$name" -v d="$desc" -v t="$title" -v r="$ref" '{
    gsub(/\{\{name\}\}/, n); gsub(/\{\{title\}\}/, t); gsub(/\{\{ref\}\}/, r)
    i = index($0, "{{description}}")
    if (i) $0 = substr($0, 1, i - 1) d substr($0, i + 15)
    print }' "${kit}/templates/stub-SKILL.md"
}

for s in $skills; do
  if [ ! -f "${kit}/skills/${s}/SKILL.md" ]; then
    fail "pinned skill ${s} does not exist in agent-kit@${ref}"; continue
  fi
  dir="${root}/.agents/skills/${s}"
  if [ "$mode" = "--render" ]; then
    rm -rf "$dir"; mkdir -p "$dir"; render "$s" > "${dir}/SKILL.md"
  fi
  [ -f "${dir}/SKILL.md" ] || { fail "missing stub .agents/skills/${s}/SKILL.md"; continue; }
  extra="$(cd "$dir" && find . -mindepth 1 ! -name SKILL.md | head -n 1)"
  [ -z "$extra" ] || fail ".agents/skills/${s} must contain only the SKILL.md stub (found ${extra#./})"
  render "$s" | cmp -s - "${dir}/SKILL.md" || fail ".agents/skills/${s}/SKILL.md differs from the rendered stub for agent-kit@${ref} (run --render)"
done

if [ -d "${root}/.agents/skills" ]; then
  for d in "${root}"/.agents/skills/*/; do
    n="$(basename "$d")"
    case " $skills " in *" $n "*) continue ;; esac
    [ ! -d "${kit}/skills/${n}" ] || fail ".agents/skills/${n} shadows a shared agent-kit skill; add it to the lock as a stub or rename it"
  done
fi

for f in $scripts; do
  [ -f "${kit}/scripts/${f}" ] || { fail "pinned script ${f} does not exist in agent-kit@${ref}"; continue; }
  if [ "$mode" = "--render" ]; then cp "${kit}/scripts/${f}" "${root}/scripts/${f}"; chmod +x "${root}/scripts/${f}"; fi
  cmp -s "${kit}/scripts/${f}" "${root}/scripts/${f}" || fail "scripts/${f} differs from agent-kit@${ref} (run --render)"
done

project="${root}/.agents/project.md"
if [ -f "$project" ]; then
  while IFS= read -r h; do
    grep -Fqx "$h" "$project" || fail ".agents/project.md is missing heading: $h"
  done < <(grep '^## ' "${kit}/templates/project.md")
else
  fail "missing .agents/project.md (start from templates/project.md)"
fi

grep -Fq "Sannrox/agent-kit" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md does not reference Sannrox/agent-kit"
grep -Fqx "## Parallel delivery lanes" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md is missing ## Parallel delivery lanes"
grep -Fq "issue-lane.sh claim" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md does not name issue-lane.sh claim"
grep -Fq "AGENTS.md" "${root}/CLAUDE.md" 2>/dev/null || fail "CLAUDE.md does not point to AGENTS.md"
grep -Fq "/.worktrees/" "${root}/.gitignore" 2>/dev/null || fail ".gitignore does not ignore /.worktrees/"

if [ "$errors" -gt 0 ]; then
  printf 'agent-kit check failed: %d problem(s) against agent-kit@%s\n' "$errors" "$ref" >&2
  exit 1
fi
printf 'agent-kit check passed (agent-kit@%s, %d stubs)\n' "$ref" "$(wc -w <<<"$skills")"
