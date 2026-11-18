---
name: tui-e2e
description: Prove terminal UI work with plain-text direction mocks, headless screen-state snapshots, a per-state key map, pseudo-terminal tests against a scripted backend, screen rules as assertions, and a crash and resume check. Use for any change to what a full-screen terminal program shows or how it reacts to keys, a terminal UI redesign, or a terminal UI Pull Request.
---

<!-- Canonical source: Sannrox/agent-kit skills/tui-e2e. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# TUI E2E

Pick the stages that match the change. A new screen or a redesign runs all of
them in order; a key-handling fix needs stages 3, 4 and 5; a copy tweak needs
stages 2 and 5 and the Pull Request gate; a change to how sessions are stored
or resumed adds stage 6. Stage 5 runs on every capture the other stages make.

This skill covers an interactive program that draws into a terminal. A
line-oriented command (arguments in, text and exit status out) is a CLI: prove
it with `validate-behavior` or the repository's CLI tests. A web UI is
`ui-e2e`.

The consuming repository's `AGENTS.md` names these under `### TUI proof` in
`## Agent skill profile`: the test command, the headless render backend and
its snapshot accept command, the pseudo-terminal driver, the scripted backend
(a fixture or setting that replaces the model, server or data source), the
terminal sizes to prove, and the live target if any. Read them first. Without
that section, find them in the repository and say in the report what you
assumed.

## 1. Direction: two or three text mocks, then stop

For a new screen or a redesign.

1. Draw two or three **distinct** mocks as plain text at the standard
   terminal size, labeled A, B, C. Distinct means a different layout or
   information model, not a different border style. Use real content from the
   product.
2. Show the states that decide the design: first run (empty), the main
   working state, a prompt waiting for the user, and one failure.
3. Follow the repository's design constraints. Put the mocks in one file in
   fenced blocks, or publish them with the HTML sharing skill when one is
   installed. Otherwise report the file path.
4. **Stop.** Wait for a pick before touching product code.

**Done:** a recorded pick, or explicit feedback to iterate on.

## 2. Screen states: headless snapshots

Render through the UI library's headless test backend, in process, with the
scripted backend. No pseudo-terminal is needed here, so these tests are fast
and belong in the default lane.

1. Snapshot every state the change touches, chosen from: empty or first run;
   working or streaming; waiting for input (a question, an approval, a
   confirmation); error and dependency unavailable; cancelled; resumed from an
   earlier session; dense (long output scrolled, many items); one long
   unbroken line; and wide characters (CJK, emoji) next to borders.
2. Render each at the standard size and a narrow size from the profile. Add a
   short height when the screen has fixed regions such as a header, an input
   box or a footer.
3. Snapshots are plain text. Read every new or changed snapshot before
   accepting it. A snapshot accepted unread is a recording, not a test.
4. Assert content with independently written expected text, not text built by
   the code under test.

**Done:** every touched state has an inspected snapshot at each listed size.

## 3. Key map: what each key does in each state

1. Write or update a table with one row per state and one column per key the
   program handles. Each cell says the effect, or "ignored". Keep it next to
   the program's own documentation when one exists.
2. Quit and cancel are defined in every state, and the footer or help hints
   name the same keys the table does.
3. Test every changed row through the headless backend: send the key, assert
   the next state and the rendered result.
4. Cover the transitions that lose input or act twice: a key pressed while a
   prompt is opening or closing, an interrupt during a prompt, a key arriving
   in the input box after the prompt it was meant for has gone, and a repeated
   confirm.

**Done:** every changed row has a passing test, and the hints match the
table.

## 4. Real terminal: the built program in a pseudo-terminal

Use the repository's existing test lane. Do not add a second runner. The value
gate and cost rules for every test come from `test-audit`
(`${AGENT_KIT_HOME:-$HOME/.agents/agent-kit}/skills/test-audit/references/writing-tests.md`).
Share one program instance across cases where the cases allow it.

1. Start the built program, not a library call, in a pseudo-terminal of a
   fixed size, with `TERM`, locale and colour settings set explicitly and the
   scripted backend selected.
2. Wait on screen conditions with a bound: poll the captured screen until it
   shows the expected text or state, and fail with the last capture when the
   bound expires. Never wait with a fixed sleep. A test that passes only after
   a longer sleep is racing.
3. Isolate each test:
   - its own temp project and state directories, named with the process id
     and a unique suffix, never one used by an earlier run. A reused directory
     can silently resume an earlier session;
   - state outside the project directory when the program works on the
     project in place;
   - a private multiplexer server or socket per test when the driver is a
     terminal multiplexer, never the default shared one.

   Another agent may run the same suite on the same machine.
4. Drive the scenarios a user meets: start, a full turn including a prompt
   answered by key, cancel, a resize while a state is shown, and quit.
5. After quit, after an interrupt, and after an error exit, assert the exit
   status and that the terminal is usable: the alternate screen is left, raw
   mode is off, and the cursor is visible.

Ask of every test: could it pass while the program is still broken for a
user? A headless render skips raw mode, input decoding and resize signals; a
scripted backend never sends what a real one sends late, twice, or not at all.

**Done:** each changed behavior has a named pseudo-terminal scenario that
passes, or a kept failure that names the unmet assertion.

## 5. Screen rules as assertions

Assert these on every snapshot and capture from stages 2 and 4, through one
shared helper that every test can call, not copied per test:

- no debug formatting of program values on screen: optional and result
  wrappers, struct dumps, quoted escapes;
- no internal names: module, type, adapter or setting keys used as prose,
  issue or decision numbers, stack traces, raw status codes;
- no raw upstream error text; an error says what failed and what the user can
  do;
- untrusted text (model output, tool output, file contents, server messages)
  cannot reach the terminal as control sequences. Feed escape and control
  characters through the scripted backend and assert, on the raw bytes the
  program wrote, that they are neutralized;
- no line wider than the terminal, and no border or column broken by wide
  characters;
- no secret on screen, in a capture, or in a test log;
- key hints match the key map from stage 3;
- the repository's copy rules (for example, banned characters).

**Done:** the helper runs on every capture and passes, or the report names
each kept failure.

## 6. Crash and resume

Only when the program keeps or resumes durable sessions, or a change touches
how it stores them. Use the real store on disk, not an in-memory one.

1. Kill the program without a graceful shutdown while a turn is in flight,
   held there by a scripted backend that blocks. Never land in the window with
   a sleep, and never add a fault hook to production code for the test.
2. Start it again on the same state. Assert that the interrupted turn is
   resumed or shown as failed, never silently lost or applied twice, and that
   the screen says the session was resumed.
3. Start a second instance on the same state while the first runs. Assert
   that it is refused or that both stay consistent, as the repository
   promises.
4. When the stored session format changed, open state written by the
   previous version with the new one, and report when the previous version
   cannot be run.

**Done:** each applicable case is recorded as passed, failed with what was
lost or duplicated, or not run with the reason.

## Live proof

Not a stage of this skill. Against a real backend or a running install, use
`validate-behavior`
(`${AGENT_KIT_HOME:-$HOME/.agents/agent-kit}/skills/validate-behavior/SKILL.md`)
with a behavior contract. It is read-only and source-blind. Read credentials
from where the repository names them, inside the script, and never type them
into the program where they would show on screen.

## Pull Request gate

A Pull Request that changes what the terminal UI shows carries inspected,
sanitized before and after text captures in fenced blocks in its body, for
every changed state at the sizes it affects. Test results and artifact links
do not substitute.

## Output

Report:

- the stages run and why the others were skipped;
- the mock file or URL, and the pick or open feedback;
- snapshot test command and results, with the states and sizes covered;
- the key map rows changed and their tests;
- pseudo-terminal scenario names and results;
- screen rule failures kept, if any;
- crash and resume results; and
- untested states, keys or sizes, and the reason.
