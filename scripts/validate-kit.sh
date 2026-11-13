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

for s in scripts/*.sh skills/*/scripts/*.sh; do bash -n "$s" || fail "syntax error in $s"; done
bash skills/deliver-ready-issue/scripts/issue-lane.sh capacity --self-test >/dev/null || fail "issue-lane.sh capacity self-test failed"

# Self-test: render a fixture consumer from the templates and check it.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.agents" "$tmp/scripts"
{ printf '# Agents\n\nShared skills: Sannrox/agent-kit.\n\n## Parallel delivery lanes\n\nLANE_AGENT=<agent> bash "$KIT/skills/deliver-ready-issue/scripts/issue-lane.sh" claim <issue>\n\n'; cat templates/agent-skill-profile.md; } > "$tmp/AGENTS.md"
printf 'See AGENTS.md\n' > "$tmp/CLAUDE.md"; printf '/.worktrees/\n' > "$tmp/.gitignore"
bash scripts/check-consumer.sh "$ROOT" "$tmp" --render >/dev/null
bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null
touch "$tmp/.agents/project.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: leftover .agents/project.md was not detected"; fi
rm "$tmp/.agents/project.md"
printf 'drift\n' >> "$tmp/.agents/skills/verify-change/SKILL.md"
if bash scripts/check-consumer.sh "$ROOT" "$tmp" >/dev/null 2>&1; then fail "self-test: drifted stub was not detected"; fi
mkdir -p "$tmp/.agents/skills/ui-e2e" && cp skills/ui-e2e/SKILL.md "$tmp/.agents/skills/ui-e2e/"
cp -r skills/ui-e2e/. "$tmp/.agents/skills/ui-e2e/"
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

# Self-test: issue-lane.sh against a fake gh. Each `gh pr view` serves the
# next Pull Request snapshot (the last one repeats); mutations are recorded.
# Issue #7 has the claim branch feat/7 and one owner marker (comments).
land="$(mktemp -d "${TMPDIR:-/tmp}/agent-kit-land.$$.XXXXXX")"; trap 'rm -rf "$tmp" "$push" "$land"' EXIT
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
printf 'agent-kit validation passed\n'
