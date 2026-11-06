---
name: ui-e2e
description: Prove web UI work with design mocks, a states gallery, browser tests against a mock backend, settled-frame screenshots, and read-only live journeys. Use for any change to how a console looks or behaves, a UI redesign, a UX audit, or a visual Pull Request.
---

<!-- Canonical source: Sannrox/agent-kit skills/ui-e2e. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# UI E2E

Pick the stages that match the work. A new surface or a redesign runs all of
them in order; a behavior fix may need only stage 3; a copy or icon tweak needs
stage 4.

The consuming repository's `AGENTS.md` names these under `### UI proof` in
`## Agent skill profile`: the browser test command, the mock backend helper,
the live test config if any, the design constraints, and where proof artifacts
go. Read them first. Without that section, find them in the repository and
say in the report what you assumed.

## 1. Direction: two or three mocks, then stop

For a new surface, a redesign, or "this looks wrong" feedback.

1. Build two or three **distinct** static mocks, labeled A, B, C. Distinct
   means a different layout or information model, not a colour swap. Use real
   content from the product, not placeholder text.
2. Show the states that decide the design, not just the happy path: at least
   first run (empty), the main working state, and one failure or unavailable
   state.
3. Follow the repository's design constraints. Put the mocks side by side in
   one self-contained HTML file. Publish it with the HTML sharing skill when
   one is installed. Otherwise report the file path.
4. **Stop.** Wait for a pick before touching product code.

**Done:** a recorded pick, or explicit feedback to iterate on.

## 2. States gallery: every state of the pick

After the pick, before or alongside implementation, for substantial layout or
component changes. Read [the gallery reference](references/gallery-and-proof.md#states-gallery).

**Done:** the reviewer has seen every listed state and replied by example ID.

## 3. Browser tests against a mock backend

Use the repository's existing browser test lane. Do not add a second runner.

1. Install the mock backend before navigation. Extend its typed options for
   any missing response instead of patching responses inside one test.
2. Act through visible controls (roles, labels, `data-*` hooks), never CSS
   paths that encode layout.
3. Assert the rendered outcome **and** the requests the UI sent: method, path,
   body and headers that matter, such as CSRF.
4. Run each new scenario at a desktop viewport and a phone viewport.
5. Turn design rules into assertions where they are checkable:
   - no horizontal overflow at either viewport;
   - readable contrast for text and controls at rest, hover and pressed;
   - no internal names in visible text: RPC or method names, issue or
     decision numbers, codenames, stack traces, raw status codes;
   - an accessibility scan (axe or the repository's equivalent) without
     serious or critical violations;
   - the repository's copy rules (for example, banned characters).

   Keep these in one shared helper that every spec can call, not copied per
   test.
6. Test isolation: bind the dev server to an ephemeral or environment-chosen
   port, and keep artifacts in a per-process directory. Another agent may run
   the same suite on the same machine.

Ask of every test: could it pass while the UI is still broken for a user? A
mock can return a shape the real backend never sends. Cover that gap with a
contract fixture shared with the backend, or with one live journey (stage 5).

**Done:** each changed behavior has a named scenario that passes, or a kept
failure that names the unmet assertion.

## 4. Visual proof

For any change to how the UI looks. Read
[the proof reference](references/gallery-and-proof.md#visual-proof).

**Done:** inspected before/after captures exist for every changed state and
viewport, with their paths in the report.

## 5. Live journeys (optional)

Against a running install, only when the repository names one and the task
allows it.

- **Read-only by default.** No create, save, publish, invite, revoke or
  delete without explicit authorization for that write.
- **Credentials:** read them from the file the repository names, inside the
  script. Never print, log, screenshot or paste a password, token or cookie.
  Redact token-bearing query parameters (`code`, `state`, `id_token_hint`) from
  any URL you output.
- **Sign out at the end.**
- **Separate backend gaps from UI failures.** A missing backend capability is
  not a UI bug, but how the UI presents the gap is.
- No hostnames, addresses or people in any artifact that leaves the machine.

**Done:** each journey step is recorded as passed, stuck (with what the user
would need to know), or blocked by a named backend gap.

## Pull Request gate

A Pull Request that changes how the UI looks carries inspected, sanitized
before/after screenshots in its body or in a comment linked from it, at the
viewports the change affects. Logs, test results and artifact links do not
substitute. If the upload fails, that is a delivery blocker, unless the user
waives it.

## Output

Report:

- the stages run and why the others were skipped;
- mock or gallery URL or path, and the pick or open feedback;
- browser test commands and results, with scenario names;
- capture paths per state and viewport;
- live journey results, with backend gaps listed separately; and
- untested states and the reason.
