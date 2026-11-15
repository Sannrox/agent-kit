# Skill flows

What each skill does when you call it: what it reads, what it decides, where
it stops, and what it hands back. The diagrams are drawn from each
`skills/<name>/SKILL.md`. When a diagram and a skill disagree, the skill is
right and the diagram is the bug.

## How to read the diagrams

```mermaid
flowchart LR
    a(["Start, result, or stop"]) --> b["A step the skill performs"]
    b --> c{"A decision"}
    c -->|"one answer"| d[["Another skill it calls"]]
    c -->|"other answer"| e(["Stop: waits for you"])
```

A result that begins with `Stop:` ends the run. The skill reports and does
nothing further until you answer.

## How the skills connect

```mermaid
flowchart TD
    idea(["Idea, bug report, or question"]) --> shape[["shape-work-item"]]
    shape --> open{"Maintainer decision<br/>still open?"}
    open -->|"yes"| triage["Issue in status:triage<br/>with a drafted decision"]
    triage -->|"you accept the draft"| capture[["capture-project-decision"]]
    capture --> ready
    open -->|"no"| ready["Issue in status:ready"]
    ready --> frontier[["advance-issue-frontier"]]
    frontier --> free{"Unblocked and<br/>unclaimed?"}
    free -->|"no"| held(["Stays blocked or active"])
    free -->|"yes"| deliver[["deliver-ready-issue"]]

    subgraph lane ["Inside one delivery lane"]
        direction TB
        impact[["assess-change-impact"]] --> gate[["test-audit<br/>authoring gate"]]
        gate --> simplify[["simplify-change"]]
        simplify --> verify[["verify-change"]]
        verify --> review["autoreview<br/>shared helper, outside the kit"]
        review --> behavior[["validate-behavior<br/>only for observable criteria"]]
    end

    deliver --> impact
    behavior --> merged(["Pull Request merged, Issue closed"])
    merged -->|"when you ask what is next"| frontier
    merged -->|"when you ask for a release"| release[["prepare-release"]]
```

Six skills stand apart from the Issue flow and run when you call them:
`improve-performance`, `ci-audit`, `ui-e2e`, `api-e2e`,
`technical-documentation`, and `refactor-docs` (which loads
`technical-documentation` first).

## shape-work-item

Call it with a raw idea, bug report, refactoring proposal, or research
question. It returns a draft Issue and never publishes without authorization.

```mermaid
flowchart TD
    start(["Raw idea, bug, refactor, or research question"]) --> read["Read AGENTS.md, README, accepted ADRs,<br/>Issue forms, and the affected code"]
    read --> dup["Search Issues, Discussions, and Pull Requests<br/>for duplicates"]
    dup --> sens{"Sensitive or<br/>exploitable?"}
    sens -->|"yes"| vuln(["Stop: private vulnerability report,<br/>never a public Issue"])
    sens -->|"no"| owner{"Owned by another<br/>repository?"}
    owner -->|"yes"| route["Route it there and record it<br/>under GitHub dependencies"]
    owner -->|"no"| classify
    route --> classify["Classify: bug, feature, refactor, or research"]
    classify --> draft["Draft: problem, observable outcome, non-goals,<br/>acceptance evidence, area, risks"]
    draft --> kind{"What kind of<br/>open question is left?"}
    kind -->|"none"| ready["Recommend status:ready"]
    kind -->|"a fact"| lookup["Look it up in code, docs,<br/>or Issue history"]
    kind -->|"routine or reversible choice"| assume["Decide it, mark it Assumed:<br/>in the body"]
    kind -->|"the question of a research Issue"| research["It is the outcome.<br/>Name question, time box, decision form"]
    kind -->|"is this wanted at all?"| need{"Report, request, incident,<br/>or blocked Issue shows the need?"}
    kind -->|"cross-boundary, public contract,<br/>trust model, hard to reverse"| decision["Draft the decision<br/>for the recommended option"]
    lookup --> ready
    assume --> ready
    research --> ready
    need -->|"yes"| ready
    need -->|"no"| nofile(["Stop: recommend not filing,<br/>name the evidence that would change that"])
    decision --> triage["Issue stays in status:triage"]
    ready --> out(["Draft Issue, labels, possible duplicates"])
    triage --> blocked(["Stop: draft Issue plus the decision<br/>for you to accept or reject"])
```

## advance-issue-frontier

Call it to ask what is ready next, or after a merge. It reports only, unless
you explicitly ask it to update Issue state.

```mermaid
flowchart TD
    start(["What is ready next, or a merge just landed"]) --> live["Read live Issues, Pull Requests, claim branches,<br/>assignments, and local worktrees"]
    live --> script["frontier.sh classifies every open Issue<br/>from its GitHub dependencies section"]
    script --> dep{"Dependency state"}
    dep -->|"anomalous: missing reference,<br/>self-dependency, cycle"| anomaly["Keep blocked, report the evidence"]
    dep -->|"blocked"| blockedIssue["Blocked: list the open dependencies"]
    dep -->|"judgment: prose, Pull Request reference,<br/>closed without completion"| judge{"Closure consistent with<br/>the dependency wording?"}
    judge -->|"no"| blockedIssue
    judge -->|"yes"| claim
    dep -->|"ready"| claim{"Claim on GitHub?"}
    claim -->|"open Pull Request, claim branch,<br/>or assignment under six hours"| active["Active: report the lane owner"]
    claim -->|"assignment over six hours,<br/>no branch, no Pull Request"| hint["Ready, with an ownership hint<br/>for you to decide"]
    claim -->|"none"| candidate["Ready candidate"]
    hint --> candidate
    candidate --> cap{"Lane capacity left<br/>under the three-lane limit?"}
    cap -->|"no"| queue["Listed, not recommended now"]
    cap -->|"yes"| collide{"Depends on, or shares a surface with,<br/>another candidate?"}
    collide -->|"yes"| seq["Recommend in sequence"]
    collide -->|"no"| par["Recommend as a parallel lane"]
    anomaly --> mutate
    blockedIssue --> mutate
    active --> mutate
    queue --> mutate
    seq --> mutate
    par --> mutate{"Did you authorize<br/>Issue updates?"}
    mutate -->|"no"| report(["Frontier report, nothing changed"])
    mutate -->|"yes"| apply["frontier.sh --apply relabels status:ready<br/>and status:blocked, then re-reads"]
    apply --> report2(["Frontier report plus every Issue it changed"])
```

It never claims a lane, starts a branch, assigns anyone, or picks priority.

## deliver-ready-issue

Call it with one ready Issue. How far it goes depends on what you asked for:
**Implement** (local change, verified), **Publish** (plus commit, push, ready
Pull Request), or **Land** (plus merge and cleanup). When your request is
unclear it takes the lower ceiling.

### Before any code

```mermaid
flowchart TD
    start(["One Issue and an authority ceiling"]) --> next{"You asked for the<br/>next Issue, unnamed?"}
    next -->|"yes"| needPick(["Stop: needs your selection or a<br/>frontier recommendation"])
    next -->|"no"| read["Read repository rules, the Issue,<br/>linked decisions, live state"]
    read --> ok{"Open, dependencies closed,<br/>one Pull Request in size,<br/>testable acceptance criteria?"}
    ok -->|"no"| notReady(["Stop: report the smallest action<br/>that would unblock it"])
    ok -->|"yes"| claim{"issue-lane.sh check"}
    claim -->|"claimed by another lane"| stalled{"Stalled on this machine: no file<br/>changed for 30 minutes, no checks running?"}
    stalled -->|"no"| foreign(["Stop: not yours, unless you<br/>direct the takeover"])
    stalled -->|"yes"| takeover["issue-lane.sh takeover: same branch and worktree,<br/>previous owner's token fenced"]
    takeover --> code
    claim -->|"old assignment, no branch"| ask(["Stop: asks you before claiming"])
    claim -->|"mine"| worktree
    claim -->|"free"| ceiling{"Ceiling is<br/>Implement only?"}
    ceiling -->|"yes"| unclaimed["Work unclaimed and say so:<br/>invisible to other machines"]
    ceiling -->|"no"| take{"issue-lane.sh claim"}
    take -->|"lost the race, or<br/>no free lane"| lost(["Stop: report, never use<br/>a differently named branch"])
    take -->|"claimed"| worktree["Check the claim branch out in<br/>.worktrees/issue-N"]
    unclaimed --> code(["Continue to implementation"])
    worktree --> code
```

### Implement and verify

```mermaid
flowchart TD
    start(["Lane worktree ready"]) --> impact[["assess-change-impact"]]
    impact --> fits{"One reviewable<br/>Pull Request?"}
    fits -->|"no"| split(["Stop: recommend a split"])
    fits -->|"yes"| build["Implement one outcome. Each new or changed<br/>test passes the test-audit authoring gate"]
    build --> simplify[["simplify-change"]]
    simplify --> verify[["verify-change"]]
    verify --> review{"autoreview:<br/>accepted findings?"}
    review -->|"yes"| fix["Fix, rerun tests"]
    fix --> review
    review -->|"no"| observable{"Acceptance criteria a user<br/>or operator can observe?"}
    observable -->|"yes"| behavior[["validate-behavior<br/>in a fresh subagent"]]
    behavior --> verdict{"Any clause fails?"}
    verdict -->|"yes"| fix2["Fix, rerun the affected clauses"]
    fix2 --> behavior
    verdict -->|"no"| scope
    observable -->|"no"| scope["Inspect the final diff for scope,<br/>secrets, and runtime state"]
    scope --> ceiling{"Ceiling"}
    ceiling -->|"Implement"| handoff(["Stop: handoff report, nothing published"])
    ceiling -->|"Publish or Land"| publish(["Continue to publish"])
```

### Publish and land

```mermaid
flowchart TD
    start(["Verified, reviewed change"]) --> base{"main is an ancestor<br/>of the branch?"}
    base -->|"no"| refresh["Refresh onto main,<br/>rerun affected checks"]
    refresh --> push
    base -->|"yes"| push["issue-lane.sh push, draft Pull Request,<br/>then mark it ready"]
    push --> ceiling{"Ceiling"}
    ceiling -->|"Publish"| url(["Stop: returns the Pull Request URL"])
    ceiling -->|"Land"| land["issue-lane.sh land watches the checks and<br/>squash-merges pinned to the reviewed head"]
    land --> result{"Result"}
    result -->|"head moved"| rereview["Review the new head"]
    result -->|"timed out"| again["Not mergeable yet:<br/>keep watching"]
    result -->|"failed check, conflict,<br/>or behind main"| cause{"Caused by<br/>this change?"}
    cause -->|"yes"| repair["Fix, push"]
    cause -->|"no, also fails on main"| inherited["Name it in the Pull Request. Accept it<br/>only if the check is not required"]
    rereview --> land
    again --> land
    repair --> land
    inherited --> land
    result -->|"merged, Issue closed"| clean["Remove the lane worktree and branch"]
    clean --> line{"Fix also needed on<br/>a maintenance line?"}
    line -->|"yes"| backport["One cherry-pick Pull Request per<br/>supported line, newest to oldest"]
    line -->|"no"| done
    backport --> done(["Completion report"])
```

It never reruns CI to chase green, never queues auto-merge, and never picks
the next Issue on its own.

## assess-change-impact

Call it before implementing or reviewing a change whose reach is unclear.
`deliver-ready-issue` runs it first in every lane. It has no branches: it
walks five questions and returns a matrix.

```mermaid
flowchart TD
    start(["An Issue, a request, or a diff"]) --> read["Read the request, README, ADRs, the code,<br/>and for a diff every changed file with its callers"]
    read --> bounds["Trace boundaries: ownership, security,<br/>configuration, CLI, logs, packaging"]
    bounds --> compat["Name compatibility and failure obligations:<br/>pins, partial failure, retries, cleanup"]
    compat --> evidence["Map each material risk to a check,<br/>or record it as residual uncertainty"]
    evidence --> artifacts["List durable artifacts that must change:<br/>README, docs, examples, ADR, upstream Issues"]
    artifacts --> out(["Matrix: surface, evidence found,<br/>required change or check, risk if missed"])
    out --> extra(["Plus scope boundaries, blocking questions,<br/>and the smallest safe Pull Request split"])
```

It does not approve an architecture or perform a security audit.

## test-audit

Two entry points: the authoring gate for a new or changed test, and an audit
that prunes existing ones. A static or slow test is not disposable for that
reason alone.

```mermaid
flowchart TD
    start(["A test"]) --> mode{"New or changed test,<br/>or an audit of existing ones?"}

    mode -->|"new or changed"| q1{"Protects observable behavior,<br/>an invariant, or a contract?"}
    q1 -->|"no"| reject(["Rejected"])
    q1 -->|"yes"| q2{"A credible regression<br/>makes it fail?"}
    q2 -->|"no"| reject
    q2 -->|"yes"| q3{"Existing proof<br/>already covers it?"}
    q3 -->|"yes"| extend["Extend the owning suite or table.<br/>No second owner"]
    q3 -->|"no"| q4{"Needs an export, flag, or hook<br/>with no production caller?"}
    q4 -->|"yes"| move["Move the proof to the real boundary"]
    q4 -->|"no"| junk{"Junk pattern? Self-comparison, mock echo,<br/>call-shape assertion, source grep"}
    junk -->|"yes"| reject
    junk -->|"no"| keep(["Kept. A regression must fail before<br/>the fix and pass after"])
    extend --> keep
    move --> keep

    mode -->|"audit"| campaign{"Whole subsystem?"}
    campaign -->|"yes"| plan["Read CAMPAIGN.md first"]
    campaign -->|"no"| inspect
    plan --> inspect["Read the candidate's owners,<br/>callers, and history"]
    inspect --> low{"Low-value proof: a junk pattern,<br/>or a duplicate of an owner test?"}
    low -->|"no"| retained(["Retained"])
    low -->|"yes"| bar{"Still guards an independent contract: API, protocol,<br/>config, migration, storage, security, release?"}
    bar -->|"yes"| retained
    bar -->|"no"| record["Record the proof that remains,<br/>delete the test and any obsolete seam"]
    record --> prove["Run owner and sibling proof,<br/>changed checks, then autoreview"]
    prove --> report(["Report: causes, retained contracts,<br/>proof and cost, line deltas"])
```

## simplify-change

Call it on your own finished diff, before review. `deliver-ready-issue` runs
it on every lane.

```mermaid
flowchart TD
    start(["A complete diff against the merge base"]) --> mine{"Review-only<br/>request?"}
    mine -->|"yes"| findings(["Findings only, no edits"])
    mine -->|"no"| derive["Re-derive the smallest complete fix<br/>from the base, using owners already present"]
    derive --> hunk{"Every hunk serves<br/>the stated outcome?"}
    hunk -->|"no"| drop["Drop the hunk or move it<br/>to its own Pull Request"]
    hunk -->|"yes"| size
    drop --> size{"Over about 800 changed lines,<br/>or 500 of complex logic?"}
    size -->|"yes"| layer["Cut to the smallest layer<br/>that can land first"]
    size -->|"no"| arch
    layer --> arch["Remove unnecessary architecture: duplicate owners,<br/>new state, redundant paths, forwarding wrappers"]
    arch --> unclear{"History leaves a<br/>path's purpose unclear?"}
    unclear -->|"yes"| keepPath["Keep it and report it"]
    unclear -->|"no"| product
    keepPath --> product{"Would need a product decision<br/>or break a contract?"}
    product -->|"yes"| finding["Report it as a finding for the owner"]
    product -->|"no"| tests
    finding --> tests{"Each test group names a<br/>distinct failure it catches?"}
    tests -->|"no"| prune["Remove duplicates, mock echoes, static assertions,<br/>and test-only hooks"]
    tests -->|"yes"| prove
    prune --> prove["Rerun the reproduction and focused checks"]
    prove --> report(["Report: what disappeared, what is still protected,<br/>production and test line deltas"])
```

No change is a valid result when the existing shape is justified.

## verify-change

Call it to get exact evidence that a change works. It runs deterministic
checks only and does not replace autoreview.

```mermaid
flowchart TD
    start(["A diff and its stated outcome"]) --> classify["Classify every changed path"]
    classify --> risk{"Risk unclear?"}
    risk -->|"yes"| impact[["assess-change-impact"]]
    risk -->|"no"| focused
    impact --> focused["Run focused tests for the affected module,<br/>then the checks its surface requires"]
    focused --> ship{"Ship-level handoff?"}
    ship -->|"yes"| gates["Run the same gates as CI,<br/>with the commands from AGENTS.md"]
    ship -->|"no, you asked for<br/>a narrower check"| tests
    gates --> tests{"Diff adds or<br/>changes tests?"}
    tests -->|"yes"| audit{"Passes the test-audit<br/>authoring gate?"}
    audit -->|"no"| remove["Remove it or move it<br/>to its owning boundary"]
    audit -->|"yes"| fail
    remove --> fail
    tests -->|"no"| fail{"Any check failed?"}
    fail -->|"yes"| pre{"Also fails without<br/>the change?"}
    pre -->|"yes, compared"| existing["Report as pre-existing, with evidence"]
    pre -->|"no"| blocking["Report as caused by the change"]
    fail -->|"no"| report
    existing --> report
    blocking --> report(["Report: commands and results, behavior covered,<br/>skipped checks with reasons, remaining uncertainty"])
```

Skipped service or kernel tests are named with their reason and residual risk.

## validate-behavior

Call it in a fresh agent that has not seen the implementation. It judges the
running product against a contract, never the code.

```mermaid
flowchart TD
    start(["A running target"]) --> contract{"Behavior contract<br/>exists?"}
    contract -->|"no"| write["Write a short one from the<br/>acceptance criteria or the request"]
    contract -->|"yes"| prepare
    write --> prepare["Private temp workspace. Prepare access:<br/>URL, command, endpoint, fixtures"]
    prepare --> live{"Target is live?"}
    live -->|"yes"| readonly["Read-only checks only"]
    live -->|"no, local or mock"| full["Mutating checks allowed"]
    readonly --> tasks
    full --> tasks["Perform each user task<br/>through user-facing surfaces"]
    tasks --> source{"Cannot continue<br/>without reading source?"}
    source -->|"yes"| blockedSource(["Stop: blocked_source_required"])
    source -->|"no"| probes["Anti-cheat probes: vary data, retry, empty and<br/>boundary input, restart and check persistence"]
    probes --> clause{"Verdict per clause"}
    clause -->|"contract met,<br/>with evidence"| pass["pass"]
    clause -->|"violated, fake state,<br/>or thin evidence"| failed["fail"]
    clause -->|"access, credentials,<br/>or tools missing"| blocked["blocked"]
    clause -->|"excluded, or an open<br/>product decision"| oos["out_of_scope"]
    pass --> report
    failed --> report
    blocked --> report
    oos --> report(["Report: counts, each failure with<br/>reproduction steps, probes run, blockers"])
    report -->|"after a fix"| rerun["Rerun the affected clauses<br/>and nearby probes"]
    rerun --> clause
```

## capture-project-decision

Call it after a Discussion, Issue, or Pull Request has settled a choice.

```mermaid
flowchart TD
    start(["A settled Discussion, Issue, or Pull Request"]) --> read["Read the full source and the<br/>current docs or code"]
    read --> accepted{"Accepted, not<br/>merely proposed?"}
    accepted -->|"no"| debate(["Stop: unresolved debate<br/>is not turned into policy"])
    accepted -->|"yes"| theirs{"Owned by another<br/>repository?"}
    theirs -->|"yes"| link(["Record it there and link from here"])
    theirs -->|"no"| pick{"Which artifact has<br/>a future reader?"}
    pick -->|"durable boundary, trust model,<br/>public contract, persistence"| adr{"docs/decisions<br/>exists?"}
    pick -->|"repeated operator or<br/>contributor knowledge"| docs["Documentation"]
    pick -->|"a supported path best<br/>taught as code"| example["Example"]
    pick -->|"a repeated agent procedure"| skill["Skill"]
    pick -->|"local to the closed work item"| none(["Nothing promoted. It stays<br/>in the closed Issue or Pull Request"])
    adr -->|"yes"| write["New ADR from the template, next number,<br/>source links, index updated"]
    adr -->|"no"| other["Record it where AGENTS.md says,<br/>or state that no ADR path exists"]
    write --> check
    other --> check
    docs --> check
    example --> check
    skill --> check["Check links, examples, Skill metadata, indexes"]
    check --> out(["Artifacts chosen, why each is durable,<br/>files changed, owner, validation"])
```

A superseded ADR gets a new ADR and a cross-link. The old text stays.

## prepare-release

Call it for release readiness, a version bump, or a release. The ceiling is
**Prepare** (audit and go/no-go), **Publish** (plus the version-bump Pull
Request), or **Release** (plus landing it and verifying the published
release). The agent never creates, signs, pushes, moves, or deletes a tag.

```mermaid
flowchart TD
    start(["A target version and a ceiling"]) --> lineQ{"Patch for a line older than<br/>the newest final release?"}
    lineQ -->|"yes"| maint["Base is the release-line branch"]
    lineQ -->|"no"| main["Base is main"]
    maint --> bound
    main --> bound["Bound the contents: base tag, commit, merged<br/>Pull Requests, the version milestone"]
    bound --> audit["Classify changes, check SemVer fit, audit<br/>versions, configuration, packaging, rollback"]
    audit --> verify[["verify-change"]]
    verify --> notes["Draft release notes and the<br/>CHANGELOG.md section"]
    notes --> go{"Checks pass, no blocker,<br/>upgrade and rollback explicit?"}
    go -->|"no-go"| nogo(["Stop: no-go report with blockers"])
    go -->|"go"| c1{"Ceiling"}
    c1 -->|"Prepare"| prepared(["Stop: go report, nothing published"])
    c1 -->|"Publish or Release"| bump["Release worktree. Commit version source,<br/>lockfiles, and the changelog section only"]
    bump --> pr["Open the version-bump Pull Request,<br/>mark it ready when checks pass"]
    pr --> c2{"Ceiling"}
    c2 -->|"Publish"| url(["Stop: returns the Pull Request URL"])
    c2 -->|"Release"| merge["Squash-merge pinned to the reviewed head.<br/>Record the release commit"]
    merge --> tag(["Stop: hands you the exact tag command<br/>and waits for you to push it"])
    tag -->|"you report the tag pushed"| tagOk{"Tag annotated, signed, and<br/>on the release commit?"}
    tagOk -->|"no"| wrong(["Stop: blocker for you.<br/>The tag is never moved or reused"])
    tagOk -->|"yes"| wf{"Repository has a<br/>release workflow?"}
    wf -->|"no"| draft(["Draft GitHub Release from the changelog.<br/>You publish it"])
    wf -->|"yes"| run{"Workflow passed?"}
    run -->|"no, workflow defect"| fixwf["Fix lands on main,<br/>rerun the same tag"]
    fixwf --> run
    run -->|"no, defect in tagged content"| newver(["Stop: needs a new pre-release<br/>or patch version"])
    run -->|"yes"| published["Verify the published release: not a draft,<br/>body matches the changelog, artifacts attached"]
    published --> final{"Final release with no open<br/>Issues in its milestone?"}
    final -->|"yes"| close["Close the version milestone"]
    final -->|"no"| report
    close --> report(["Release report"])
```

## improve-performance

Call it for measured performance work. A cache is the last step, not the
first.

```mermaid
flowchart TD
    start(["A slow flow"]) --> rule["Write the acceptance rule in the Pull Request<br/>before the first run"]
    rule --> measure["Measure the real flow: operation counts first,<br/>baseline and candidate interleaved, median and p95"]
    measure --> needed{"For each counted operation:<br/>does this request need it?"}
    needed -->|"yes"| leave["Leave it"]
    needed -->|"no"| del{"Can it be deleted with<br/>every contract still held?"}
    del -->|"yes"| deleted["Delete the waste"]
    del -->|"no"| once{"Can the owner do it once<br/>and callers reuse the fact?"}
    once -->|"yes"| owner["Do it once at the owner,<br/>carry the fact through the hot path"]
    once -->|"no"| batch{"Independent work that batches<br/>without hurting tails or cold start?"}
    batch -->|"yes"| batched["Batch it"]
    batch -->|"no"| cache["Cache, with a written reason, full-identity key,<br/>owner invalidation, a bound, and a work-count test"]
    leave --> rerun
    deleted --> rerun
    owner --> rerun
    batched --> rerun
    cache --> rerun["Rerun the same workload<br/>under the same rule"]
    rerun --> worse{"Any user-facing<br/>metric worse?"}
    worse -->|"yes"| accept(["Stop: needs the owner's<br/>explicit acceptance"])
    worse -->|"no"| gain{"Measurable gain?"}
    gain -->|"no"| revert(["Revert the change"])
    gain -->|"yes"| out(["Pull Request evidence: workload, rule,<br/>before and after table, waste removed"])
```

## ci-audit

Two entry points: the admission gate for a new job or a wider trigger, and an
audit of the jobs a repository already runs. Zero failures alone never
condemns a job.

```mermaid
flowchart TD
    start(["A CI job"]) --> mode{"New job or wider trigger,<br/>or an audit of existing jobs?"}

    mode -->|"new or wider"| g1{"Catches a failure<br/>no existing job catches?"}
    g1 -->|"no"| reject(["Rejected"])
    g1 -->|"yes"| g2{"Can it be a step<br/>in an existing job?"}
    g2 -->|"yes"| step(["Added as a step"])
    g2 -->|"no"| g3["Pick the latest trigger that still catches it:<br/>Pull Request, default-branch push, schedule, release"]
    g3 --> g4["Scope the trigger to the paths that can break it"]
    g4 --> g5{"Longest job on<br/>a Pull Request?"}
    g5 -->|"yes"| justify(["Admitted, with the wall-time cost<br/>justified in the Pull Request"])
    g5 -->|"no"| admit(["Admitted"])

    mode -->|"audit"| measure["Run scripts/ci-report.sh over<br/>at least a week of normal work"]
    measure --> alone{"Failed alone<br/>in the window?"}
    alone -->|"yes"| wall{"Sets the wall time?"}
    wall -->|"no"| keep(["Keep"])
    wall -->|"yes"| speed[["improve-performance"]]
    alone -->|"no"| skipped{"Skipped<br/>every time?"}
    skipped -->|"yes"| narrow["Narrow the workflow trigger<br/>or split the workflow"]
    skipped -->|"no"| outside{"Fails for reasons<br/>outside the diff?"}
    outside -->|"yes"| soft["Non-blocking on Pull Requests,<br/>strict on a schedule"]
    outside -->|"no"| bar{"Reports elsewhere, guards a rare costly break,<br/>or was added on purpose?"}
    bar -->|"yes"| keep
    bar -->|"no"| order["Scope by path, else move to a later trigger,<br/>else merge, else delete and name the owning job"]
    narrow --> required
    soft --> required
    order --> required{"Changes a required check?"}
    required -->|"yes"| protect["Update the required checks first,<br/>or gate on one aggregate job"]
    required -->|"no"| report
    protect --> report
    speed --> report
    report(["Report: window, wall time, table, one decision per job.<br/>Rerun after the changes land"])
```

## ui-e2e

Call it for UI work. It picks stages by the kind of change, and the direction
stage always stops for your pick.

```mermaid
flowchart TD
    start(["A UI change"]) --> kind{"What kind of change?"}
    kind -->|"new surface, redesign,<br/>or it looks wrong"| mocks["Stage 1: two or three distinct static mocks<br/>with empty, working, and failure states"]
    kind -->|"behavior fix"| tests
    kind -->|"copy or icon tweak"| proof
    mocks --> pickStop(["Stop: waits for your pick"])
    pickStop -->|"you pick one"| gallery["Stage 2: states gallery of the pick"]
    gallery --> seen(["Stop: waits for your reply<br/>by example ID"])
    seen -->|"you reply"| tests["Stage 3: browser tests against the mock backend,<br/>desktop and phone, design rules as assertions"]
    tests --> looks{"Changes how<br/>the UI looks?"}
    looks -->|"yes"| proof["Stage 4: inspected before and after<br/>captures per state and viewport"]
    looks -->|"no"| liveQ
    proof --> liveQ{"Repository names a live install<br/>and the task allows it?"}
    liveQ -->|"yes"| live["Stage 5: live journeys, read-only,<br/>sign out at the end"]
    liveQ -->|"no"| gate
    live --> gate{"Visual change with screenshots<br/>in the Pull Request?"}
    gate -->|"upload failed"| blocker(["Stop: delivery blocker,<br/>unless you waive it"])
    gate -->|"yes, or not a visual change"| out(["Report: stages run and skipped, picks,<br/>test results, capture paths, untested states"])
```

## api-e2e

Call it for a change to an interface the repository serves. It picks stages
by what the change touches, and a breaking change without a new version stops
for your decision.

```mermaid
flowchart TD
    start(["A change to a served interface"]) --> wire{"Changes what<br/>crosses the wire?"}
    wire -->|"yes"| contract["Stage 1: change the contract source, regenerate,<br/>run the drift check, classify the change"]
    wire -->|"no"| tests
    contract --> kind{"Additive or<br/>breaking?"}
    kind -->|"additive"| replay["Prove both directions: previous requests on the new server,<br/>new requests on the previous server"]
    kind -->|"breaking"| version{"Ships as a new version<br/>beside the old one?"}
    version -->|"yes"| replay
    version -->|"no"| decide(["Stop: the owner decides"])
    decide -->|"you record a decision"| replay
    replay --> tests["Stage 2: boundary tests against the real listener,<br/>real client, interface rules as assertions"]
    tests --> durable{"Touches durable state, idempotency, background work,<br/>startup, shutdown, or health?"}
    durable -->|"yes"| crash["Stage 3: kill with a write in flight and restart,<br/>readiness, version overlap, takeover and fencing<br/>where an instance owns work exclusively"]
    durable -->|"no"| out
    crash --> out(["Report: stages run and skipped, drift result,<br/>version pairs proven, test results, what mocks cannot prove"])
```

## technical-documentation

Call it to build or review documentation, including `AGENTS.md` and
`CONTRIBUTING.md`.

```mermaid
flowchart TD
    start(["A documentation task"]) --> classify["Classify: build or review,<br/>brownfield or evergreen"]
    classify --> inventory["Inventory governance files, docs directories,<br/>framework sources, READMEs"]
    inventory --> langs{"More than<br/>one language?"}
    langs -->|"yes"| parity["Set the required parity level"]
    langs -->|"no"| rules
    parity --> rules["Read the agent and contributing rules,<br/>the principles, and a repository overlay if one exists"]
    rules --> mode{"Build or review?"}
    mode -->|"build"| build["Follow references/build.md"]
    mode -->|"review"| review["Follow references/review.md"]
    build --> broad
    review --> broad{"Repo-wide, multi-framework,<br/>or high-conflict?"}
    broad -->|"yes"| agents["Sub-agents: inventory, governance,<br/>docs framework, then synthesis"]
    broad -->|"no"| sweep
    agents --> sweep["Sweep governance and content for defects"]
    sweep --> fixmode{"You asked for<br/>report-only?"}
    fixmode -->|"yes"| findings(["Findings with next actions"])
    fixmode -->|"no"| fixed(["High-confidence defects fixed, plus<br/>validation notes and remaining gaps"])
```

## refactor-docs

Call it with one target page to rewrite, split, or shorten. A rewrite never
discards a behavior fact silently.

```mermaid
flowchart TD
    start(["A target docs page"]) --> clear{"Target page missing<br/>or ambiguous?"}
    clear -->|"yes"| ask(["Stop: one concise question"])
    clear -->|"no"| load[["technical-documentation"]]
    load --> type["Choose the main page type"]
    type --> mixed{"Page mixes<br/>page types?"}
    mixed -->|"yes"| plan["Plan a destination for the rest: reference,<br/>troubleshooting, or guide page"]
    mixed -->|"no"| facts
    plan --> facts["Inventory every fact on the old page"]
    facts --> each{"For each fact"}
    each -->|"keep"| stay["Stays on the target page"]
    each -->|"belongs elsewhere"| moved["Moved to a named existing or new page,<br/>linked from the target"]
    each -->|"obsolete"| proofQ{"Current source<br/>proves it?"}
    proofQ -->|"yes"| deleted["Deleted, with the source-backed reason"]
    proofQ -->|"no"| stay
    stay --> rewrite
    moved --> rewrite
    deleted --> rewrite["Rewrite: purpose first, recommended path<br/>before alternatives"]
    rewrite --> compare["Compare old and new: every fact<br/>kept, moved, or retired"]
    compare --> verifiable{"A behavior claim<br/>cannot be verified?"}
    verifiable -->|"yes"| uncertain["Remove it, mark the uncertainty,<br/>or ask for the source"]
    verifiable -->|"no"| check
    uncertain --> check["Check links, formatting, and the<br/>commands and examples on the page"]
    check --> out(["Report: what changed, what moved where,<br/>source checks, validation"])
```
