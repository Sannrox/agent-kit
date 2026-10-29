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
bash skills/deliver-ready-issue/scripts/issue-lane.sh capacity --self-test >/dev/null || fail "issue-lane.sh capacity self-test failed"

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

# Self-test: issue-lane.sh land against a fake gh. Each `gh pr view` serves the
# next Pull Request snapshot (the last one repeats); mutations are recorded.
land="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-land.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$push" "$land"' EXIT
mkdir -p "$land/bin"
cat > "$land/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "repo view --json nameWithOwner"*) echo o/r ;;
  "repo view --json defaultBranchRef"*) echo main ;;
  "api user"*) echo me ;;
  "issue view 7 --json state"*) cat "$FAKE/issue_state" ;;
  "issue view 7 --json"*) echo '{"number":7,"title":"feat: x","state":"OPEN","labels":[],"assignees":[],"closedByPullRequestsReferences":[]}' ;;
  "api graphql"*) head -n 1 "$FAKE/seq"; [ "$(wc -l < "$FAKE/seq")" -gt 1 ] && sed -i.bak 1d "$FAKE/seq"; true ;;
  "pr merge"* | "api -X DELETE"* | "api -X PUT"*) echo "$*" >> "$FAKE/calls" ;;
  "api repos/o/r/compare/"*) echo ahead ;;
  "api repos/o/r/commits/"*) echo true ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$land/bin/gh"
# The fake git serves the claim branch from branch_sha ("absent" for none,
# "error" for a failed lookup), answers `remote get-url` from origin, and
# records pushes; everything else goes to the real git.
real_git="$(command -v git)"
cat > "$land/bin/git" <<FAKE
#!/usr/bin/env bash
case "\$1" in
  ls-remote) sha="\$(cat "\$FAKE/branch_sha")"; [ "\$sha" = absent ] && exit 2; [ "\$sha" = error ] && exit 128; printf '%s\trefs/heads/feat/7\n' "\$sha" ;;
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
optional_red='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","isRequired":true},{"name":"fuzz","status":"COMPLETED","conclusion":"FAILURE","isRequired":false}]'
lane() { # expected-exit dir args...
  local code=0 want="$1" dir="$2"; shift 2
  out="$(cd "$dir" && FAKE="$land" ISSUE_LANE_POLL_SECONDS=0 PATH="$land/bin:$PATH" \
    bash "$ROOT/skills/deliver-ready-issue/scripts/issue-lane.sh" "$@" 2>&1)" || code=$?
  [ "$code" = "$want" ] || fail "self-test: issue-lane $* exited $code, expected $want: $out"
}
run_land() { lane "$1" "$land" land 7 --pr 9 --head "$H" "${@:2}"; }
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
snap OPEN "$H" false '[]' CLEAN | jq -c '.checksComplete = false' > "$land/seq"
run_land 5
if grep -q 'merge_method' "$land/calls"; then fail "self-test: land merged without seeing every check"; fi

# Self-test: push adopts a publish that stopped before syncing: GitHub holds a
# copy of HEAD (same tree, parent already local) that HEAD does not contain.
rg() { git -C "$land/repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$land/repo" && rg init -q && rg checkout -q -b feat/7 && printf 'a\n' > "$land/repo/f" && rg add f && rg commit -qm base
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
if (cd "$land/repo" && FAKE="$land" PATH="$land/bin:$PATH" \
  bash "$ROOT/skills/deliver-ready-issue/scripts/issue-lane.sh" push 7 >/dev/null 2>&1); then
  fail "self-test: push treated a committed mode change as already published"
fi
printf 'agent-kit validation passed\n'
