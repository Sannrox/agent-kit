#!/usr/bin/env bash
# Validate the canonical skills in this repository and self-test the consumer check.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
fail() { printf 'agent-kit validation failed: %s\n' "$1" >&2; exit 1; }
require_line() { grep -Fqx "$2" "$1" || fail "$1 is missing canonical line: $2"; }

# The kit uses its own canonical skills through the same link chain consumers use.
[ "$(readlink .agents/skills)" = ../skills ] || fail ".agents/skills must be a symlink to ../skills"
[ "$(readlink .claude/skills)" = ../.agents/skills ] || fail ".claude/skills must be a symlink to ../.agents/skills"

for f in skills/*/SKILL.md; do
  n="$(basename "$(dirname "$f")")"
  [ "$(sed -n 1p "$f")" = "---" ] || fail "$f has no frontmatter"
  require_line "$f" "name: ${n}"
  grep -q '^description: .\+' "$f" || fail "$f has no description"
  grep -q '^# ' "$f" || fail "$f has no title heading"
done

# Shared skills stay generic: product facts belong in the consumer's AGENTS.md.
if grep -rIn -i -E '\b(kako|kekkai|mizuchi|hoshi|tenkai|rusui|mikura|aldunis)\b|shikigami GitHub|sekai-chisei (release|change|design)' \
  skills; then
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
for stage in '## Establish the authority ceiling' '## Prepare the release' '## Publish the version bump' \
  '## Establish the release' '## Output' '## Boundaries'; do
  require_line skills/prepare-release/SKILL.md "$stage"
done
for ref in references/parallel-delivery.md scripts/issue-lane.sh; do
  [ -f "skills/deliver-ready-issue/${ref}" ] || fail "missing skills/deliver-ready-issue/${ref}"
  grep -Fq "$ref" skills/deliver-ready-issue/SKILL.md || fail "deliver-ready-issue does not link ${ref}"
done
[ -f skills/prepare-release/references/maintenance-lines.md ] || fail "missing skills/prepare-release/references/maintenance-lines.md"
grep -Fq references/maintenance-lines.md skills/prepare-release/SKILL.md || fail "prepare-release does not link references/maintenance-lines.md"
grep -Fqx -- '- Release only from a commit on `main` or the matching maintenance line.' skills/prepare-release/SKILL.md \
  || fail "prepare-release is missing canonical line: - Release only from a commit on \`main\` or the matching maintenance line."
grep -Fqx -- '- Never cut the newest release from a maintenance line.' skills/prepare-release/SKILL.md \
  || fail "prepare-release is missing canonical line: - Never cut the newest release from a maintenance line."
grep -Fq 'origin/release-<line>' skills/prepare-release/SKILL.md || fail "prepare-release version bump does not name a maintenance-line base"
grep -Fq 'maintenance line is not latest.' skills/prepare-release/SKILL.md \
  || fail "prepare-release still treats every final release as latest"
grep -Fq 'git cherry-pick -x' skills/deliver-ready-issue/SKILL.md || fail "deliver-ready-issue does not name the maintenance-line backport"
grep -Eq 'issue-lane\.sh"?[[:space:]]+check' skills/advance-issue-frontier/SKILL.md || fail "advance-issue-frontier does not use issue-lane.sh check"
grep -Fq scripts/frontier.sh skills/advance-issue-frontier/SKILL.md || fail "advance-issue-frontier does not use scripts/frontier.sh"
grep -Fq scripts/ci-report.sh skills/ci-audit/SKILL.md || fail "ci-audit does not use scripts/ci-report.sh"
# #78: a skill's `references/...` or `../...` path resolves from the file that names it.
for f in skills/*/SKILL.md skills/*/references/*.md; do
  while IFS= read -r p; do
    [ -e "$(dirname "$f")/$p" ] || fail "$f names $p, which does not resolve from its directory"
  done < <(grep -oE '`(references/|\.\./)[A-Za-z0-9_./-]+\.md`' "$f" | tr -d '`' || true)
done

for s in scripts/*.sh skills/*/scripts/*.sh; do bash -n "$s" || fail "syntax error in $s"; done
bash skills/deliver-ready-issue/scripts/issue-lane.sh capacity --self-test >/dev/null || fail "issue-lane.sh capacity self-test failed"

# Self-test: render a fixture consumer from the templates and check it.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.agents" "$tmp/scripts"
{ printf '# Agents\n\nShared skills: Sannrox/agent-kit.\n\n## Parallel delivery lanes\n\nLANE_AGENT=<agent> bash "$KIT/skills/deliver-ready-issue/scripts/issue-lane.sh" claim <issue>\n\n'; cat templates/agent-skill-profile.md; } > "$tmp/AGENTS.md"
printf 'See AGENTS.md\n' > "$tmp/CLAUDE.md"; printf '/.worktrees/\n' > "$tmp/.gitignore"
bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null
# #77: an Optional: heading may be left out; a required one may not.
cp "$tmp/AGENTS.md" "$tmp/AGENTS.full"
grep -Fqx '### Additional impact boundaries' "$tmp/AGENTS.md" || fail "self-test: the fixture lacks the optional slot, so removing it proves nothing"
awk '/^### Additional impact boundaries$/{skip=1; next} /^#/{skip=0} !skip' "$tmp/AGENTS.full" > "$tmp/AGENTS.md"
grep -Fq 'Additional impact' "$tmp/AGENTS.md" && fail "self-test: the optional slot was not removed"
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null || fail "self-test: check-consumer required the optional Additional impact boundaries heading"
grep -vFx '### Release audit' "$tmp/AGENTS.full" > "$tmp/AGENTS.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: a missing required profile heading was not detected"; fi
mv "$tmp/AGENTS.full" "$tmp/AGENTS.md"
# #58: --render writes vendored scripts without changing the consumer's mode.
vendored="$tmp/scripts/validate-workflow-skills.sh"
[ ! -x "$vendored" ] || fail "self-test: --render created a vendored script with the executable bit"
chmod +x "$vendored"; bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
[ -x "$vendored" ] || fail "self-test: --render dropped the executable bit a consumer tracks"
chmod -x "$vendored"; bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
[ ! -x "$vendored" ] || fail "self-test: --render added the executable bit to a consumer's non-executable script"
touch "$tmp/.agents/project.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: leftover .agents/project.md was not detected"; fi
rm "$tmp/.agents/project.md"
# CLAUDE.md as a symlink to an AGENTS.md that never names itself must pass;
# a symlink to any other file must not.
grep -Fq AGENTS.md "$tmp/AGENTS.md" && fail "self-test: the fixture AGENTS.md names itself, so the symlink case proves nothing"
ln -sf AGENTS.md "$tmp/CLAUDE.md"
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null || fail "self-test: CLAUDE.md as a symlink to AGENTS.md was rejected"
printf 'See AGENTS.md\n' > "$tmp/other.md"; ln -sf other.md "$tmp/CLAUDE.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: CLAUDE.md as a symlink to another file was accepted"; fi
rm "$tmp/CLAUDE.md" "$tmp/other.md"; printf 'See AGENTS.md\n' > "$tmp/CLAUDE.md"
rm "$tmp/.claude/skills"
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null || fail "self-test: a consumer without the .claude/skills link must still pass"
bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
[ "$(readlink "$tmp/.claude/skills")" = ../.agents/skills ] || fail "self-test: --render did not link .claude/skills to .agents/skills"
rm "$tmp/.claude/skills" && mkdir "$tmp/.claude/skills"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null 2>&1; then fail "self-test: a real .claude/skills directory was accepted"; fi
[ -d "$tmp/.claude/skills" ] && [ ! -L "$tmp/.claude/skills" ] || fail "self-test: --render replaced a real .claude/skills directory"
rmdir "$tmp/.claude/skills"
printf 'drift\n' >> "$tmp/.agents/skills/verify-change/SKILL.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: drifted stub was not detected"; fi
mkdir -p "$tmp/.agents/skills/ui-e2e" && cp skills/ui-e2e/SKILL.md "$tmp/.agents/skills/ui-e2e/"
cp -r skills/ui-e2e/. "$tmp/.agents/skills/ui-e2e/"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: vendored shared skill was not detected"; fi
bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null

# Self-test (#64): the vendored wrapper checks against the latest main of an
# existing kit checkout. A checkout on another branch keeps its branch and
# commit; one on main fast-forwards. The fixture kit's origin holds this
# tree on main; the feature branch drops check-consumer.sh, so only a check
# against main passes.
kfx="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-wrapper.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$kfx"' EXIT
kg() { git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "${@:2}"; }
mkdir "$kfx/origin" && git ls-files -z | xargs -0 tar -cf - | tar -xf - -C "$kfx/origin"
kg "$kfx/origin" init -q -b main && kg "$kfx/origin" add -A && kg "$kfx/origin" commit -qm kit
git clone -q "$kfx/origin" "$kfx/kit"
kg "$kfx/kit" checkout -q -b feature && kg "$kfx/kit" rm -q scripts/check-consumer.sh && kg "$kfx/kit" commit -qm "drop check"
feature="$(kg "$kfx/kit" rev-parse HEAD)"
wrap() { AGENT_KIT_HOME="$kfx/kit" bash "$tmp/scripts/validate-workflow-skills.sh" 2>&1; }
out="$(wrap)" || fail "self-test: the wrapper did not check a feature-branch kit against main: $out"
[ "$(kg "$kfx/kit" symbolic-ref --short HEAD)" = feature ] && [ "$(kg "$kfx/kit" rev-parse HEAD)" = "$feature" ] \
  || fail "self-test: the wrapper moved the kit checkout off its branch"
kg "$kfx/kit" checkout -q main && kg "$kfx/origin" commit -q --allow-empty -m newer
out="$(wrap)" || fail "self-test: the wrapper failed on a kit checkout on main: $out"
[ "$(kg "$kfx/kit" rev-parse HEAD)" = "$(kg "$kfx/origin" rev-parse HEAD)" ] || fail "self-test: the wrapper did not fast-forward a kit checkout on main"
rm -rf "$kfx"

# Self-test: frontier.sh against a fake gh serving fixture Issues of o/r.
# Referenced Issues: 1 completed, 2 open, 3 not planned, x/y#4 completed in
# another repository, 404 missing. Relabels are recorded in calls.
fr="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-frontier.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$fr"' EXIT
mkdir -p "$fr/bin"
cat > "$fr/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "issue list -R o/r"*) cat "$FAKE/issues" ;;
  "label list -R o/r"*) echo '["status:ready","status:blocked","status:triage"]' ;;
  "api repos/o/r/issues/1 "*) echo '{"state":"closed","reason":"completed","pr":false}' ;;
  "api repos/o/r/issues/2 "*) [ -f "$FAKE/down" ] && { echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1; }
    echo '{"state":"open","reason":null,"pr":false}' ;;
  "api repos/o/r/issues/3 "*) echo '{"state":"closed","reason":"not_planned","pr":false}' ;;
  "api repos/x/y/issues/4 "*) echo '{"state":"closed","reason":"completed","pr":false}' ;;
  "api repos/o/r/issues/1"[0-9]" "*) echo '{"state":"open","reason":null,"pr":false}' ;;
  "api repos/o/r/issues/404 "*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  "issue edit"*) echo "$*" >> "$FAKE/calls" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$fr/bin/gh"
fixture() { # number labels-csv dependency-section
  jq -cn --argjson n "$1" --arg l "$2" --arg d "$3" \
    '{number: $n, title: "t\($n)", labels: [$l | split(",")[] | select(. != "") | {name: .}],
      body: "## Summary\n\nx\n\n## GitHub dependencies\n\n\($d)\n\n### Checklist\n\n- [x] done\n"}'
}
{ fixture 10 status:blocked '- none'
  fixture 11 status:ready '- #1
- x/y#4 (delivered)'
  fixture 12 status:ready '- https://github.com/o/r/issues/2'
  fixture 13 status:ready 'Blocked on a week of play after Sannrox/r#1 (delivered).'
  fixture 14 status:ready '- #404'
  fixture 15 status:ready '- #15'
  fixture 16 status:ready '- #17'
  fixture 17 status:blocked '- #16'
  fixture 18 status:ready,status:triage '- #2'
  fixture 19 '' '- #2'
  fixture 20 status:ready '- #3'
  jq -cn '{number: 21, title: "t21", labels: [{name: "status:ready"}], body: "no section"}'
  fixture 22 status:ready,status:blocked '- none'
  fixture 23 status:blocked '- #1 (after the owner approves)'
  fixture 24 status:blocked '- #2
- #3'
  # #48: a plain "Dependencies" heading is read; with both, "GitHub dependencies" wins.
  fixture 25 status:ready '- #2' | jq -c '.body |= sub("## GitHub dependencies"; "### dependencies")'
  fixture 26 status:ready '- #1' | jq -c '.body += "\n## Dependencies\n\n- #2\n"'
} | jq -s . > "$fr/issues"
frontier() { # expected-exit args...
  local code=0 want="$1"; shift
  out="$(FAKE="$fr" PATH="$fr/bin:$PATH" bash skills/advance-issue-frontier/scripts/frontier.sh --repo o/r "$@" 2>&1)" || code=$?
  [ "$code" = "$want" ] || fail "self-test: frontier.sh $* exited $code, expected $want: $out"
}
: > "$fr/calls"
frontier 0 --json
[ ! -s "$fr/calls" ] || fail "self-test: frontier.sh without --apply relabeled: $(cat "$fr/calls")"
want='{"10":"ready","11":"ready","12":"blocked","13":"judgment","14":"anomalous","15":"anomalous","16":"anomalous","17":"anomalous","18":"blocked","19":"blocked","20":"judgment","21":"judgment","22":"ready","23":"judgment","24":"judgment","25":"blocked","26":"ready"}'
printf '%s' "$out" | jq -e --argjson w "$want" '[.issues[] | {key: (.number | tostring), value: .state}] | from_entries == $w' >/dev/null \
  || fail "self-test: frontier.sh states differ from $want: $out"
printf '%s' "$out" | jq -e '(.issues[] | select(.number == 21) | .why | test("GitHub dependencies.*Dependencies"))
  and (.issues[] | select(.number == 26) | .why | test("ignored .Dependencies"))' >/dev/null \
  || fail "self-test: frontier.sh did not name the dependency headings it read or looked for: $out"
frontier 0 --apply
sort "$fr/calls" | diff - <(printf '%s\n' \
  'issue edit 10 -R o/r --add-label status:ready --remove-label status:blocked' \
  'issue edit 12 -R o/r --add-label status:blocked --remove-label status:ready' \
  'issue edit 14 -R o/r --add-label status:blocked --remove-label status:ready' \
  'issue edit 15 -R o/r --add-label status:blocked --remove-label status:ready' \
  'issue edit 16 -R o/r --add-label status:blocked --remove-label status:ready' \
  'issue edit 22 -R o/r --remove-label status:blocked' \
  'issue edit 25 -R o/r --add-label status:blocked --remove-label status:ready') >/dev/null \
  || fail "self-test: frontier.sh --apply made the wrong edits: $(cat "$fr/calls")"
: > "$fr/calls"; touch "$fr/down"
frontier 1 --apply
[ ! -s "$fr/calls" ] || fail "self-test: frontier.sh relabeled from a partial view: $(cat "$fr/calls")"
rm "$fr/down"

# Self-test: ci-report.sh against a fake gh serving the runs of o/r. Commit a
# passes. On b only CI / build fails, and the Scan run is a rerun. Commit c has
# a superseded CI run (5) that passed and a newer one (6) where build and lint
# fail together. CI / deploy is skipped every time.
ci="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-ci.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$fr" "$ci"' EXIT
mkdir -p "$ci/bin" "$ci/jobs"
cat > "$ci/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "run list -R o/r --event pull_request --status completed --limit 300 "*) cat "$FAKE/runs" ;;
  "api --paginate repos/o/r/actions/runs/"*)
    id="${3#repos/o/r/actions/runs/}"; id="${id%%/*}"
    [ -f "$FAKE/down" ] && [ "$id" = 7 ] && { echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1; }
    jq -c "$5" "$FAKE/jobs/$id" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$ci/bin/gh"
ci_run() { # id workflow sha created-at attempt
  jq -cn --argjson id "$1" --arg w "$2" --arg s "$3" --arg c "$4" --argjson a "$5" \
    '{databaseId: $id, workflowName: $w, headSha: $s, createdAt: $c, attempt: $a}'
}
ci_job() { # name conclusion hour seconds
  jq -cn --arg n "$1" --arg c "$2" --arg h "$3" --argjson s "$4" \
    '("2026-01-01T\($h):00:" ) as $t
     | {name: $n, conclusion: $c, created_at: "\($t)00Z",
        started_at: (if $c == "skipped" then "\($t)00Z" else "\($t)10Z" end),
        completed_at: (if $c == "skipped" then "\($t)00Z"
                       else ("\($t)10Z" | fromdateiso8601 + $s | todateiso8601) end)}'
}
ci_jobs() { jq -s '{jobs: .}' > "$ci/jobs/$1"; }
{ ci_run 1 CI a 2026-01-01T00:00:00Z 1; ci_run 2 Scan a 2026-01-01T00:00:00Z 1
  ci_run 3 CI b 2026-01-01T01:00:00Z 1; ci_run 4 Scan b 2026-01-01T01:00:00Z 2
  ci_run 5 CI c 2026-01-01T02:00:00Z 1; ci_run 6 CI c 2026-01-01T02:00:30Z 1
  ci_run 7 Scan c 2026-01-01T02:00:00Z 1
} | jq -s . > "$ci/runs"
{ ci_job build success 00 600; ci_job lint success 00 60; ci_job deploy skipped 00 0; } | ci_jobs 1
ci_job scan success 00 300 | ci_jobs 2
{ ci_job build failure 01 180; ci_job lint success 01 60; ci_job deploy skipped 01 0; } | ci_jobs 3
ci_job scan success 01 300 | ci_jobs 4
{ ci_job build success 02 600; ci_job lint success 02 60; ci_job deploy skipped 02 0; } | ci_jobs 5
{ ci_job build failure 02 600; ci_job lint failure 02 60; ci_job deploy skipped 02 0; } | ci_jobs 6
ci_job scan success 02 300 | ci_jobs 7
ci_report() { # expected-exit args...
  local code=0 want="$1"; shift
  out="$(FAKE="$ci" PATH="$ci/bin:$PATH" bash skills/ci-audit/scripts/ci-report.sh --repo o/r "$@" 2>&1)" || code=$?
  [ "$code" = "$want" ] || fail "self-test: ci-report.sh $* exited $code, expected $want: $out"
}
ci_report 0 --json
# ran, skipped, failed, failed alone, last (b is a rerun, so it sets no wall time), median seconds
want='{"CI / build":[3,0,2,1,2,600],"CI / deploy":[0,3,0,0,0,null],"CI / lint":[3,0,1,0,0,60],"Scan / scan":[3,0,0,0,0,300]}'
printf '%s' "$out" | jq -e --argjson w "$want" \
  '([.jobs[] | {key: "\(.workflow) / \(.job)", value: [.ran, .skipped, .failed, .failed_alone, .last, .median_s]}] | from_entries == $w)
   and ([.runs, .rerun_runs, .commits, .clean_commits, .wall_median_s] == [6, 1, 3, 2, 610])' >/dev/null \
  || fail "self-test: ci-report.sh report differs from $want: $out"
ci_report 0
printf '%s\n' "$out" | grep -Fq '| CI / build | 3 | 0 | 0 | 2 | 1 | 10 | 10 | 10 | 2 | 23 |' \
  || fail "self-test: ci-report.sh table lacks the CI / build row: $out"
touch "$ci/down"
ci_report 1 --json
printf '%s' "$out" | grep -q '"jobs"' && fail "self-test: ci-report.sh reported from a partial view: $out"
rm "$ci/down"

# Self-test: gh-verified-push.sh warns once per pushed file that becomes
# 100755 (added, or changed from 100644), and not for a modified file that
# already was. A dry run with --repo and --expected-oid never touches the
# network; a failing gh stub proves it.
push="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-push.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$fr" "$ci" "$push"' EXIT
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
# #63: adding a symlink, or retyping a path to or from one, is refused before
# any GitHub call, naming the path; deleting one is publishable.
dry_push() { (cd "$push/repo" && PATH="$push/bin:$PATH" bash "$ROOT/scripts/gh-verified-push.sh" \
  --repo o/r --branch b --expected-oid "$1" --dry-run 2>&1); }
base="$(g rev-parse HEAD)"; ln -s plain.sh "$push/repo/link" && g add link && g commit -qm link
if out="$(dry_push "$base")"; then fail "self-test: gh-verified-push accepted a symlink addition: $out"; fi
printf '%s\n' "$out" | grep -q '^Refusing link: .*symlink' || fail "self-test: symlink refusal did not name the path: $out"
base="$(g rev-parse HEAD)"; rm "$push/repo/link" && printf 'x\n' > "$push/repo/link" && g add link && g commit -qm retype
if out="$(dry_push "$base")"; then fail "self-test: gh-verified-push accepted a symlink retyped to a file: $out"; fi
printf '%s\n' "$out" | grep -q '^Refusing link: ' || fail "self-test: type-change refusal did not name the path: $out"
base="$(g rev-parse HEAD~1)"; g rm -q link && g commit -qm "drop link"
out="$(dry_push "$base")" || fail "self-test: gh-verified-push refused deleting a symlink: $out"

# Self-test: issue-lane.sh against a fake gh. Each `gh pr view` serves the
# next Pull Request snapshot (the last one repeats); mutations are recorded.
# Issue #7 has the claim branch feat/7 and one owner marker (comments).
# Comments are stateful: deleting one removes it, `gh issue comment` appends
# id 99 (after the markers in rival, when that file exists), and marker_gone
# makes a marker delete fail as if another caller had removed it.
land="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-land.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$fr" "$ci" "$push" "$land"' EXIT
mkdir -p "$land/bin"
cat > "$land/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "repo view --json nameWithOwner"*) echo o/r ;;
  "repo view --json defaultBranchRef"*) echo main ;;
  "api user"*) echo me ;;
  "issue view 7 --json state"*) cat "$FAKE/issue_state" ;;
  "issue view 7 --json"*) cat "$FAKE/issue_json" ;;
  "api repos/o/r/issues/7/timeline"*) echo '[]' ;;
  "api repos/o/r/issues/7/comments"*) cat "$FAKE/comments" ;;
  "api repos/o/r/collaborators/"*) echo true ;;
  "api repos/o/r/git/matching-refs/heads/"*) echo '[{"ref":"refs/heads/feat/7","object":{"sha":"x"}}]' ;;
  "pr list"*) echo '[]' ;;
  "api repos/o/r/commits/feat/7 --jq .commit.committer.date") echo 2026-01-01T00:00:00Z ;;
  "api graphql"*) case "$*" in *--input*) cat >> "$FAKE/graphql_in" ;; esac; head -n 1 "$FAKE/seq"; [ "$(wc -l < "$FAKE/seq")" -gt 1 ] && sed -i.bak 1d "$FAKE/seq"; true ;;
  "api -X DELETE repos/o/r/issues/comments/"*) [ -f "$FAKE/marker_gone" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    last="${*: -1}"; jq -c --argjson id "${last##*/}" 'map(select(.id != $id))' "$FAKE/comments" > "$FAKE/comments.new" && mv "$FAKE/comments.new" "$FAKE/comments"
    echo "$*" >> "$FAKE/calls" ;;
  "issue comment 7 --body "*) echo "issue comment 7" >> "$FAKE/calls"
    jq -c --arg body "$5" --argjson rival "$(cat "$FAKE/rival" 2>/dev/null || echo '[]')" \
      '. + $rival + [{id: 99, created_at: "2026-03-01T00:00:00Z", user: {login: "me"}, body: $body}]' "$FAKE/comments" > "$FAKE/comments.new" \
      && mv "$FAKE/comments.new" "$FAKE/comments" ;;
  "issue edit 7 --add-assignee"*) echo "$*" >> "$FAKE/calls" ;;
  "pr merge"* | "api -X DELETE"* | "api -X PUT"* | "api -X POST"*) echo "$*" >> "$FAKE/calls" ;;
  "api repos/o/r --jq .node_id") echo R_1 ;;
  "api repos/o/r/git/commits/"*) printf '{"tree":{"sha":"%s"}}\n' "$(cat "$FAKE/tree")" ;;
  "api repos/o/r/compare/"*) echo ahead ;;
  "api repos/o/r/commits/"*) echo true ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$land/bin/gh"
# The fake git serves the claim branch from branch_sha ("absent" for none,
# "error" for a failed lookup) and main from default_sha, answers
# `remote get-url` from origin, and records pushes; the scratch branch of push
# --rebased is absent; everything else goes to the real git.
real_git="$(command -v git)"
cat > "$land/bin/git" <<FAKE
#!/usr/bin/env bash
case "\$1" in
  ls-remote) case "\$*" in *lane-publish/*) exit 2 ;; esac
    case "\$*" in *refs/heads/main) printf '%s\trefs/heads/main\n' "\$(cat "\$FAKE/default_sha")"; exit 0 ;; esac
    sha="\$(cat "\$FAKE/branch_sha")"; [ "\$sha" = absent ] && exit 2; [ "\$sha" = error ] && exit 128; printf '%s\trefs/heads/feat/7\n' "\$sha" ;;
  push | fetch) echo "git \$*" >> "\$FAKE/calls" ;;
  remote) cat "\$FAKE/origin"; case "\$*" in *--push*) [ -f "\$FAKE/push_origin" ] && cat "\$FAKE/push_origin" ;; esac; true ;;
  *) exec "$real_git" "\$@" ;;
esac
FAKE
chmod +x "$land/bin/git"
H=1111111111111111111111111111111111111111
snap() { # state head auto(true|false) checks merge-state
  jq -cn --arg s "$1" --arg h "$2" --argjson a "$3" --argjson c "$4" --arg m "$5" \
    '{number: 9, title: "feat: x", state: $s, isDraft: false, headRefName: "feat/7", headRefOid: $h, mergeStateStatus: $m,
      isCrossRepository: false, baseRefName: (if $s == "BASE" then "release" else "main" end), autoMergeRequest: (if $a then {} else null end), statusCheckRollup: $c,
      mergeCommit: (if $s == "MERGED" then {oid: "2222222222222222222222222222222222222222"} else null end),
      closingIssuesReferences: [{number: 7}]}'
}
pending='[{"name":"ci","status":"IN_PROGRESS","conclusion":"","isRequired":true}]'
red='[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}]'
optional_pending='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","isRequired":true},{"name":"semver","status":"IN_PROGRESS","conclusion":"","isRequired":false}]'
unprotected_pending='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","isRequired":false},{"name":"semver","status":"IN_PROGRESS","conclusion":"","isRequired":false}]'
optional_red='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","isRequired":true},{"name":"fuzz","status":"COMPLETED","conclusion":"FAILURE","isRequired":false}]'
lane_agent=a lane_token=lane-token-7
lane() { # expected-exit dir args...; LANE_AGENT and LANE_TOKEN from lane_agent and lane_token
  local code=0 want="$1" dir="$2"; shift 2
  out="$(cd "$dir" && FAKE="$land" ISSUE_LANE_POLL_SECONDS=0 PATH="$land/bin:$PATH" \
    LANE_AGENT="$lane_agent" LANE_TOKEN="$lane_token" \
    bash "$ROOT/skills/deliver-ready-issue/scripts/issue-lane.sh" "$@" 2>&1)" || code=$?
  [ "$code" = "$want" ] || fail "self-test: issue-lane $* exited $code, expected $want: $out"
}
run_land() { lane "$1" "$land" land 7 --pr 9 --head "$H" "${@:2}"; }
issue_fixture='{"number":7,"title":"feat: x","state":"OPEN","labels":[],"assignees":[],"closedByPullRequestsReferences":[]}'
printf '%s\n' "$issue_fixture" > "$land/issue_json"
# The marker holds the sha256 prefix of lane-token-7; only that token owns the lane.
printf '[{"id":1,"created_at":"2026-01-01T00:00:00Z","user":{"login":"me"},"body":"%s"}]\n' \
  '<!-- issue-lane-claim agent=a token-sha256=a5d72c097890699d -->' > "$land/comments"
: > "$land/calls"

# Self-test: lane ownership follows the token, not the shared login.
lane_agent="" lane 1 "$land" claim 7
printf '%s\n' "$out" | grep -q LANE_AGENT || fail "self-test: claim without LANE_AGENT did not name it: $out"
lane 0 "$land" check 7 --json
printf '%s' "$out" | jq -e '.verdict == "mine" and .mine and .owner.agent == "a"' >/dev/null \
  || fail "self-test: check with the claim token is not mine: $out"
lane_token=wrong lane 3 "$land" check 7 --json
printf '%s' "$out" | jq -e '.verdict == "claimed" and (.mine | not)' >/dev/null \
  || fail "self-test: check with a wrong token is not claimed: $out"
lane_token="" lane 3 "$land" check 7
lane_token="" lane 1 "$land" release 7
if grep -q DELETE "$land/calls"; then fail "self-test: release without the token deleted something"; fi
lane_token=wrong lane 3 "$land" push 7
lane_token=wrong lane 3 "$land" land 7 --pr 9 --head "$H"
[ ! -s "$land/calls" ] || fail "self-test: push or land acted on a lane that is not mine: $(cat "$land/calls")"
# Prefixed type labels derive the lane branch when the title has no type.
jq -c '.title = "x" | .labels = [{name: "type:refactor"}]' <<< "$issue_fixture" > "$land/issue_json"
lane 0 "$land" check 7 --json
printf '%s' "$out" | jq -e '.lane_branch == "refactor/7"' >/dev/null || fail "self-test: type:refactor did not derive refactor/7: $out"
printf '%s\n' "$issue_fixture" > "$land/issue_json"

: > "$land/calls"; echo CLOSED > "$land/issue_state"; echo "$H" > "$land/branch_sha"; echo git@github.com:o/r.git > "$land/origin"
{ snap OPEN "$H" true "$pending" BLOCKED; snap OPEN "$H" false "$pending" BLOCKED; snap OPEN "$H" false '[]' CLEAN
  snap MERGED "$H" false '[]' MERGED; } > "$land/seq"
run_land 0
grep -q -- '--disable-auto' "$land/calls" || fail "self-test: land kept an auto-merge queued while watching"
grep -qx "api -X PUT repos/o/r/pulls/9/merge -f merge_method=squash -f sha=$H -f commit_title=feat: x (#9)" "$land/calls" \
  || fail "self-test: land did not merge pinned to the reviewed head"
if grep -q -- '--auto' "$land/calls"; then fail "self-test: land queued a GitHub auto-merge, which later pushes can outlive"; fi
grep -qx "git push --quiet --force-with-lease=refs/heads/feat/7:$H origin :refs/heads/feat/7" "$land/calls" \
  || fail "self-test: land did not delete the claim branch under a lease on the merged head"
printf '%s\n' "$out" | grep -q '"verdict": "merged"' || fail "self-test: land did not report the merge: $out"
: > "$land/calls"
snap OPEN 3333333333333333333333333333333333333333 true "$pending" BLOCKED > "$land/seq"
run_land 4
grep -q -- '--disable-auto' "$land/calls" || fail "self-test: land did not withdraw auto-merge for a moved head"
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged an unreviewed head"; fi
: > "$land/calls"
{ snap OPEN "$H" false "$pending" BLOCKED; snap OPEN "$H" false "$red" BLOCKED; } > "$land/seq"
run_land 5
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged after a failed check"; fi
: > "$land/calls"; echo OPEN > "$land/issue_state"
snap MERGED "$H" false '[]' MERGED > "$land/seq"
run_land 7
if grep -q 'git push' "$land/calls"; then fail "self-test: land deleted the claim branch before the Issue closed"; fi
: > "$land/calls"; echo CLOSED > "$land/issue_state"; echo 4444444444444444444444444444444444444444 > "$land/branch_sha"
run_land 7
if grep -q 'git push' "$land/calls"; then fail "self-test: land deleted a claim branch that moved past the merged head"; fi
echo absent > "$land/branch_sha"
run_land 0
echo error > "$land/branch_sha"
run_land 7
echo "$H" > "$land/branch_sha"; echo git@github.com:fork/r.git > "$land/origin"; : > "$land/calls"
run_land 7
if grep -q 'git push' "$land/calls"; then fail "self-test: land deleted a branch through an origin that is not the repository"; fi
echo git@github.com:o/r.git > "$land/origin"; echo git@github.com:fork/r.git > "$land/push_origin"; : > "$land/calls"
run_land 7
if grep -q 'git push' "$land/calls"; then fail "self-test: land deleted a branch through a push URL that is not the repository"; fi
rm "$land/push_origin"
: > "$land/calls"
snap BASE "$H" false '[]' CLEAN > "$land/seq"
run_land 1
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged into a non-default base"; fi
echo git@github.com:o/r.git > "$land/origin"; : > "$land/calls"
{ snap OPEN "$H" false '[]' CLEAN; snap MERGED "$H" false '[]' MERGED; } > "$land/seq"
run_land 0 --timeout-min 0

# A failed optional check blocks until named as inherited; a required one
# blocks even when named.
echo CLOSED > "$land/issue_state"; echo "$H" > "$land/branch_sha"; : > "$land/calls"
snap OPEN "$H" false "$optional_red" UNSTABLE > "$land/seq"
run_land 5
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged over an unaccepted optional failure"; fi
{ snap OPEN "$H" false "$optional_red" UNSTABLE; snap MERGED "$H" false '[]' MERGED; } > "$land/seq"
run_land 0 --accept-failed fuzz
grep -q 'merge_method=squash' "$land/calls" || fail "self-test: land did not merge over an accepted optional failure"
: > "$land/calls"
snap OPEN "$H" false "$red" BLOCKED > "$land/seq"
run_land 5 --accept-failed ci
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land accepted a failed required check"; fi
# Only required checks hold the merge; with none required, every check does.
: > "$land/calls"
{ snap OPEN "$H" false "$optional_pending" UNSTABLE; snap MERGED "$H" false '[]' MERGED; } > "$land/seq"
run_land 0
grep -q 'merge_method=squash' "$land/calls" || fail "self-test: land waited on an optional check after the required ones passed"
printf '%s\n' "$out" | grep -q 'optional checks still run: semver' || fail "self-test: land did not name the pending optional check: $out"
: > "$land/calls"
snap OPEN "$H" false "$unprotected_pending" UNSTABLE > "$land/seq"
run_land 6 --timeout-min 0
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged before CI finished on a branch with no required check"; fi
snap OPEN "$H" false '[]' CLEAN | jq -c '.checksComplete = false' > "$land/seq"
run_land 5
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged without seeing every check"; fi

# Self-test: push adopts a publish that stopped before syncing: GitHub holds a
# copy of HEAD (same tree, parent already local) that HEAD does not contain.
rg() { git -C "$land/repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$land/repo" && rg init -q && rg checkout -q -b feat/7 && printf 'a\n' > "$land/repo/f" && rg add f && rg commit -qm base
rg rev-parse HEAD > "$land/default_sha"
printf 'b\n' > "$land/repo/f" && rg commit -qam work
rg commit-tree "$(rg rev-parse 'HEAD^{tree}')" -p "$(rg rev-parse HEAD^)" -m published > "$land/branch_sha"
lane 0 "$land/repo" push 7
[ "$(rg rev-parse HEAD)" = "$(cat "$land/branch_sha")" ] || fail "self-test: push did not adopt the published copy of HEAD"
rg commit -q --allow-empty -m noop
lane 0 "$land/repo" push 7
[ "$(rg rev-parse HEAD)" = "$(cat "$land/branch_sha")" ] || fail "self-test: push left HEAD off the PR head when nothing changed"
rg update-index --chmod=+x f && rg commit -qm exec
rg commit-tree "$(rg rev-parse 'HEAD^{tree}')" -p "$(rg rev-parse HEAD^)" -m published > "$land/branch_sha"
rg update-index --chmod=-x f && rg commit -qm "drop exec"
if (cd "$land/repo" && FAKE="$land" PATH="$land/bin:$PATH" LANE_TOKEN="$lane_token" \
  bash "$ROOT/skills/deliver-ready-issue/scripts/issue-lane.sh" push 7 >/dev/null 2>&1); then
  fail "self-test: push treated a committed mode change as already published"
fi

# Self-test: push never resets away a local rebase onto, or merge of, main
# that keeps the published tree. Main and the lane both add g; the lane's
# copy wins. T is the published lane commit on the old base.
rg checkout -q --detach HEAD~3 && rg checkout -q -b main
printf 'main\n' > "$land/repo/g" && rg add g && rg commit -qm "main adds g"
rg rev-parse HEAD > "$land/default_sha"
rg checkout -q -B feat/7 HEAD^
printf 'lane\n' > "$land/repo/g" && printf 'h\n' > "$land/repo/h" && rg add g h && rg commit -qm lane
rg rev-parse HEAD > "$land/branch_sha"
rg rebase -q -X theirs main >/dev/null
rebased="$(rg rev-parse HEAD)"
lane 1 "$land/repo" push 7
[ "$(rg rev-parse HEAD)" = "$rebased" ] || fail "self-test: push reset away a rebase onto main that keeps the published tree"
printf '%s\n' "$out" | grep -q 'rebased.*push 7 --rebased' || fail "self-test: push did not name the rebase recovery: $out"
rg reset -q --hard "$(cat "$land/branch_sha")" && rg merge -q -s ours -m "merge main" main
merged="$(rg rev-parse HEAD)"
lane 1 "$land/repo" push 7
[ "$(rg rev-parse HEAD)" = "$merged" ] || fail "self-test: push reset away a merge of main that keeps the published tree"
printf '%s\n' "$out" | grep -q 'merges another branch.*push 7 --rebased' || fail "self-test: push did not name the merge recovery: $out"

# Self-test: push --rebased publishes the rebased lane as one verified commit
# on a scratch branch from the new base, then moves the claim branch onto it
# guarded by the published tip T. A failed publish never moves the branch.
T="$(cat "$land/branch_sha")"
rg reset -q --hard "$rebased"
rg rev-parse 'HEAD^{tree}' > "$land/tree"
copy="$(rg commit-tree "$(cat "$land/tree")" -p "$(cat "$land/default_sha")" -m published)"
: > "$land/calls"; : > "$land/graphql_in"
echo '{"errors":[{"message":"boom"}]}' > "$land/seq"
lane 1 "$land/repo" push 7 --rebased
if grep -q updateRefs "$land/graphql_in"; then fail "self-test: push --rebased moved the claim branch after a failed publish"; fi
[ "$(rg rev-parse HEAD)" = "$rebased" ] || fail "self-test: a failed push --rebased moved local HEAD"
rg commit-tree "$T^{tree}" -p "$T" -m "published elsewhere" > "$land/branch_sha"
: > "$land/calls"
lane 1 "$land/repo" push 7 --rebased
printf '%s\n' "$out" | grep -q 'never held by this checkout' || fail "self-test: push --rebased overwrote a tip it never held: $out"
if grep -q 'POST' "$land/calls"; then fail "self-test: push --rebased published over a tip it never held"; fi
echo "$T" > "$land/branch_sha"; : > "$land/calls"; : > "$land/graphql_in"
{ printf '{"data":{"createCommitOnBranch":{"commit":{"oid":"%s","url":null}}}}\n' "$copy"
  echo '{"data":{"updateRefs":{"clientMutationId":null}}}'; } > "$land/seq"
lane 0 "$land/repo" push 7 --rebased
grep -q "api -X POST repos/o/r/git/refs -f ref=refs/heads/lane-publish/7/rebase -f sha=$(cat "$land/default_sha")" "$land/calls" \
  || fail "self-test: push --rebased did not publish on a scratch branch from the new base"
jq -se --arg main "$(cat "$land/default_sha")" 'map(select(.query | contains("createCommitOnBranch")))[0].variables.input
  | .expectedHeadOid == $main and .branch.branchName == "lane-publish/7/rebase"' "$land/graphql_in" >/dev/null \
  || fail "self-test: push --rebased did not publish the delta onto the new base"
jq -se --arg t "$T" --arg c "$copy" 'map(select(.query | contains("updateRefs")))[0].variables.input.refUpdates
  == [{name: "refs/heads/feat/7", beforeOid: $t, afterOid: $c, force: true}]' "$land/graphql_in" >/dev/null \
  || fail "self-test: push --rebased did not move the claim branch guarded by the published tip"
[ "$(grep -c 'api -X DELETE repos/o/r/git/refs/heads/lane-publish/7/rebase' "$land/calls")" = 2 ] \
  || fail "self-test: push --rebased did not clear the scratch branch before and after"
[ "$(rg rev-parse HEAD)" = "$copy" ] || fail "self-test: push --rebased left HEAD off the new Pull Request head"

# Self-test (#39): the first push of a lane rebased onto a newer main, while
# the claim branch still sits at the old claim base C, publishes on main, not
# on C, without --rebased; the Pull Request then holds only the lane's work.
C="$(rg rev-parse main^)"
rg checkout -q -B feat/7 main && printf 'k\n' > "$land/repo/k" && rg add k && rg commit -qm "lane on new main"
rg rev-parse 'HEAD^{tree}' > "$land/tree"
copy="$(rg commit-tree "$(cat "$land/tree")" -p "$(cat "$land/default_sha")" -m published)"
echo "$C" > "$land/branch_sha"; : > "$land/calls"; : > "$land/graphql_in"
{ printf '{"data":{"createCommitOnBranch":{"commit":{"oid":"%s","url":null}}}}\n' "$copy"
  echo '{"data":{"updateRefs":{"clientMutationId":null}}}'; } > "$land/seq"
lane 0 "$land/repo" push 7
jq -se --arg main "$(cat "$land/default_sha")" 'map(select(.query | contains("createCommitOnBranch")))[0].variables.input.expectedHeadOid == $main' \
  "$land/graphql_in" >/dev/null || fail "self-test: first push of a rebased lane published on the old claim base: $out"
jq -se --arg c "$C" --arg p "$copy" 'map(select(.query | contains("updateRefs")))[0].variables.input.refUpdates
  == [{name: "refs/heads/feat/7", beforeOid: $c, afterOid: $p, force: true}]' "$land/graphql_in" >/dev/null \
  || fail "self-test: first push of a rebased lane did not move the claim branch guarded by the claim base"
# A checkout older than the claim tip is stale, not rebased: it is refused.
cat "$land/default_sha" > "$land/branch_sha"
rg checkout -q -B feat/7 "$C"
printf 'old\n' > "$land/repo/k" && rg add k && rg commit -qm "lane on old base"
: > "$land/calls"
lane 1 "$land/repo" push 7
if grep -q POST "$land/calls"; then fail "self-test: push moved the claim branch back onto an older base"; fi

# Self-test: takeover moves the lane to the caller and touches neither the
# branch nor a Pull Request. The lane worktree is $land/repo (feat/7 is
# checked out there); its files are fresh until age_lane backdates them.
marker7() {
  printf '[{"id":1,"created_at":"2026-01-01T00:00:00Z","user":{"login":"me"},"body":"%s"}]\n' \
    '<!-- issue-lane-claim agent=a token-sha256=a5d72c097890699d -->' > "$land/comments"
  : > "$land/calls"
}
age_lane() { find "$land/repo" -name .git -prune -o -type f -exec touch -t 202001010000 {} +; }
taken() { printf '%s\n' "$out" | sed -n '/^{/,$p' | jq -r "$1"; }
owners() { jq -r '[.[].body | capture("agent=(?<a>[a-z0-9-]+)").a] | join(",")' "$land/comments"; }
marker7
lane_agent=b lane_token=wrong lane 3 "$land/repo" takeover 7
lane_agent=b lane_token=wrong lane 3 "$land" takeover 7
[ ! -s "$land/calls" ] && [ "$(owners)" = a ] \
  || fail "self-test: takeover without the token, a stalled local lane, or --yes changed the lane: $(cat "$land/calls")"
lane_agent=b lane_token=wrong lane 0 "$land" takeover 7 --yes
[ "$(taken .basis)" = approved ] && [ "$(owners)" = b ] || fail "self-test: takeover --yes did not move the lane: $out"
marker7; age_lane
lane_agent=b lane_token=wrong lane 0 "$land/repo" takeover 7
[ "$(taken .basis)" = local-stall ] && [ "$(taken .worktree)" = . ] && [ "$(owners)" = b ] \
  || fail "self-test: takeover of a lane stalled on this machine did not move it: $out"
if grep -Eq 'git/refs|pulls|pr merge' "$land/calls"; then fail "self-test: takeover touched the branch or a Pull Request: $(cat "$land/calls")"; fi
new_token="$(taken .token)"
lane_token="$new_token" lane 0 "$land" check 7
lane 3 "$land" push 7
marker7
lane_agent=b lane 0 "$land" takeover 7
[ "$(taken .basis)" = token ] || fail "self-test: takeover with the lane token is not a rotation: $out"
lane 3 "$land" check 7
# A marker removed by a concurrent takeover or release stops this one.
marker7; touch "$land/marker_gone"
lane_agent=b lane_token=wrong lane 1 "$land/repo" takeover 7
if grep -q 'issue comment' "$land/calls"; then fail "self-test: takeover recorded an owner after losing the marker"; fi
rm "$land/marker_gone"
# A lane without an owner (an interrupted takeover) is taken over again; when
# two callers record an owner, the older marker wins and the other withdraws.
echo '[]' > "$land/comments"
lane_agent=b lane_token=wrong lane 0 "$land/repo" takeover 7
[ "$(owners)" = b ] || fail "self-test: takeover did not adopt a lane without an owner: $out"
echo '[]' > "$land/comments"
echo '[{"id":50,"created_at":"2026-02-01T00:00:00Z","user":{"login":"me"},"body":"<!-- issue-lane-claim agent=rival token-sha256=0000000000000000 -->"}]' > "$land/rival"
lane_agent=b lane_token=wrong lane 3 "$land/repo" takeover 7
[ "$(owners)" = rival ] || fail "self-test: the later of two takeovers did not withdraw: $(cat "$land/comments")"
rm "$land/rival"
printf 'agent-kit validation passed\n'
