#!/usr/bin/env bash
# Check (or render) a consuming repository against the latest agent-kit (main).
#
# Usage: check-consumer.sh <kit-dir> <repo-root> [--render]
#
# Checks:
#   - every default skill (templates/default-skills.txt) has a stub in
#     .agents/skills/<name>/ that is exactly the rendered templates/stub-SKILL.md
#     (only SKILL.md, no vendored references or scripts);
#   - any other .agents/skills/<name> that matches a kit skill (opt-in skills)
#     is also a stub, never a vendored copy;
#   - vendored scripts (templates/vendored-scripts.txt) are byte-identical to the kit
#     (validate-workflow-skills.sh; gh-verified-push.sh is optional and not listed);
#   - AGENTS.md has the ## Agent skill profile section with its contract
#     headings (templates/agent-skill-profile.md); .agents/project.md is gone;
#   - AGENTS.md references Sannrox/agent-kit and keeps the parallel-lane policy;
#     CLAUDE.md points to AGENTS.md; .gitignore ignores /.worktrees/.
# --render rewrites the default stubs, existing opt-in stubs and vendored scripts.
set -euo pipefail

kit="${1:?kit dir}"; root="${2:?repo root}"; mode="${3:-check}"
errors=0
fail() { printf 'agent-kit check: %s\n' "$1" >&2; errors=$((errors + 1)); }

skills="$(tr '\n' ' ' < "${kit}/templates/default-skills.txt")"
if [ -d "${root}/.agents/skills" ]; then
  for d in "${root}"/.agents/skills/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    case " $skills " in *" $n "*) continue ;; esac
    [ ! -f "${kit}/skills/${n}/SKILL.md" ] || skills="${skills} ${n}"
  done
fi
scripts="$(tr '\n' ' ' < "${kit}/templates/vendored-scripts.txt")"

render() { # render <skill>
  local name="$1" canon="${kit}/skills/$1/SKILL.md" desc title
  desc="$(sed -n '2,/^---$/s/^description: //p' "$canon" | head -n 1)"
  title="$(sed -n 's/^# //p' "$canon" | head -n 1)"
  awk -v n="$name" -v d="$desc" -v t="$title" '{
    gsub(/\{\{name\}\}/, n); gsub(/\{\{title\}\}/, t);
    i = index($0, "{{description}}")
    if (i) $0 = substr($0, 1, i - 1) d substr($0, i + 15)
    print }' "${kit}/templates/stub-SKILL.md"
}

for s in $skills; do
  if [ ! -f "${kit}/skills/${s}/SKILL.md" ]; then
    fail "skill ${s} does not exist in agent-kit main"; continue
  fi
  dir="${root}/.agents/skills/${s}"
  if [ "$mode" = "--render" ]; then
    rm -rf "$dir"; mkdir -p "$dir"; render "$s" > "${dir}/SKILL.md"
  fi
  [ -f "${dir}/SKILL.md" ] || { fail "missing stub .agents/skills/${s}/SKILL.md"; continue; }
  extra="$(cd "$dir" && find . -mindepth 1 ! -name SKILL.md | head -n 1)"
  [ -z "$extra" ] || fail ".agents/skills/${s} must contain only the SKILL.md stub (found ${extra#./})"
  render "$s" | cmp -s - "${dir}/SKILL.md" || fail ".agents/skills/${s}/SKILL.md differs from the rendered stub (run --render)"
done


for f in $scripts; do
  [ -f "${kit}/scripts/${f}" ] || { fail "script ${f} does not exist in agent-kit main"; continue; }
  if [ "$mode" = "--render" ]; then cp "${kit}/scripts/${f}" "${root}/scripts/${f}"; chmod +x "${root}/scripts/${f}"; fi
  cmp -s "${kit}/scripts/${f}" "${root}/scripts/${f}" || fail "scripts/${f} differs from agent-kit main (run --render)"
done

[ ! -e "${root}/.agents/project.md" ] || fail ".agents/project.md is retired; fold its unique content into ## Agent skill profile in AGENTS.md"
grep -Fqx "## Agent skill profile" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md is missing ## Agent skill profile (see templates/agent-skill-profile.md)"
grep -q '^Feature: .' "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md ## Agent skill profile is missing the Feature: line"
while IFS= read -r h; do
  grep -Fqx "$h" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md is missing heading: $h"
done < <(grep '^### ' "${kit}/templates/agent-skill-profile.md")

grep -Fq "Sannrox/agent-kit" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md does not reference Sannrox/agent-kit"
grep -Fqx "## Parallel delivery lanes" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md is missing ## Parallel delivery lanes"
grep -Fq "issue-lane.sh claim" "${root}/AGENTS.md" 2>/dev/null || fail "AGENTS.md does not name issue-lane.sh claim"
grep -Fq "AGENTS.md" "${root}/CLAUDE.md" 2>/dev/null || fail "CLAUDE.md does not point to AGENTS.md"
grep -Fq "/.worktrees/" "${root}/.gitignore" 2>/dev/null || fail ".gitignore does not ignore /.worktrees/"

if [ "$errors" -gt 0 ]; then
  printf 'agent-kit check failed: %d problem(s) against agent-kit main\n' "$errors" >&2
  exit 1
fi
printf 'agent-kit check passed (agent-kit main, %d stubs)\n' "$(wc -w <<<"$skills")"
