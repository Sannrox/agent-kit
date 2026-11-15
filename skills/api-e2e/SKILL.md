---
name: api-e2e
description: Prove a change to an interface the repository serves (HTTP, RPC, WebSocket, webhook) with a wire-contract and compatibility gate, boundary tests against a real listener, and a crash and restart check. Use for any change to an endpoint, method, payload, status code, auth rule or error shape, or when clients and servers must stay compatible across a deploy.
---

<!-- Canonical source: Sannrox/agent-kit skills/api-e2e. Repository-specific facts live in the consuming repository's AGENTS.md (## Agent skill profile and the sections it builds on). -->

# API E2E

Pick the stages that match the change. A new operation or a changed payload
runs stages 1 and 2; a behavior fix behind an unchanged contract needs only
stage 2; a change to durable state, idempotency, background work, startup,
shutdown or health checks adds stage 3.

This skill covers an interface the repository serves. For a request the
repository sends to another system, a mock proves how the request was built
and nothing about the other side: assert the final serialized request and name
the live gap in the report.

The consuming repository's `AGENTS.md` names these under `### API proof` in
`## Agent skill profile`: the contract source, the drift check command, the API
test command, the server fixture, and the contract fixture shared with client
or UI mocks if one exists. The versions that can run at the same time come from
`### Compatibility and failure obligations`. Read them first. Without that
section, find them in the repository and say in the report what you assumed.

## 1. Contract: one source, checked for drift and compatibility

For any change to what crosses the wire: an operation name or path, a payload,
a status or error code, a header, an event.

1. Find the single source of the contract (a schema, an interface definition,
   or the server's typed handlers) and change it there. Regenerate everything
   derived from it: clients, validators, reference docs, mock backends. Never
   hand-edit generated output.
2. Run the drift check. It fails when generated output differs from the
   source. When the repository has no machine-readable contract, do not
   introduce a schema language for this change. Record example exchanges
   (request and expected response) as fixtures that the server tests assert
   against.
3. Classify the change against every version that can run at the same time.
   During a deploy, old clients call new servers; during a rollback, new
   clients call old servers.
   - **Additive:** a new operation, a new optional request field, a new
     response field. It is additive only when both sides tolerate what they do
     not know: the previous client ignores the new response field, the
     previous server ignores the new request field, and the new client works
     when the previous server lacks the new operation. Where the contract
     rejects unknown request fields, a new request field is breaking.
   - **Breaking:** removing or renaming a field or operation, changing a type,
     a meaning or a default, a new required request field, stricter
     validation, a different status or error code for the same condition.

   A breaking change ships as a new version beside the old one. Shipping it
   any other way is the owner's decision: stop and present it.
4. Prove the classification in both directions.
   - Deploy: replay the previous version's recorded requests against the new
     server, and parse the new server's responses with the previous client
     contract.
   - Rollback: send the new client's requests to the previous server, or
     validate them against the previous contract when that server cannot be
     run.

   Name any direction you could not run.
5. Share the contract fixture. When a client or UI suite mocks this interface,
   its mock responses come from the same fixtures or generated types the
   server tests assert, so a mock cannot return a shape the server never
   sends.

**Done:** the drift check passes, or the example exchanges are recorded where
no machine-readable contract exists; the change is classified with its
evidence; and a breaking change has a new version or a recorded owner
decision.

## 2. Boundary tests against a real listener

Use the repository's existing test lane. Do not add a second runner. The value
gate and cost rules for every test come from `test-audit`
(`${AGENT_KIT_HOME:-$HOME/.agents/agent-kit}/skills/test-audit/references/writing-tests.md`).

1. Start the real server with its routing, middleware, auth and serialization,
   once per suite. Replace only what lives outside the process: other
   services, paid providers, the clock.
2. Call it over the real transport with the client its callers use: the
   generated client when one exists, otherwise a plain protocol client. Never
   call handler functions directly.
3. Assert the response (status, body, the headers that matter) **and** the
   effect: what was stored and what was sent outward. Write expected values
   independently. Never compute them with the code under test.
4. For each changed operation, cover the rows that apply: success, invalid
   input, no credential, credential without permission, not found, conflict or
   duplicate, over a limit (size, page, rate), dependency unavailable.
5. Turn interface rules into assertions. These hold for every operation:
   - auth fails closed on an operation the contract protects: a missing,
     expired or wrong-scope credential, or a bad signature, is rejected with
     no effect, and the response does not reveal whether another tenant's
     resource exists. An operation the contract makes public is exempt;
   - errors carry no stack trace, internal name, query text, file path or
     upstream error text;
   - no secret appears in a log line or a test artifact, or in a response
     other than a credential the operation exists to issue.

   These hold only where the contract promises them:
   - an error carries the machine-readable code the contract defines;
   - a repeated write with the same idempotency key applies once and returns
     the same result;
   - unknown request fields are handled the way the contract says;
   - a list honors the contract's default and maximum page size and its
     order.

   A rule the contract does not promise is a gap to report, not a behavior to
   add here. Adding a limit, a key or stricter validation changes the
   contract and goes through stage 1.

   Keep the assertions in one shared helper that every test can call, not
   copied per test.
6. Test isolation: bind an ephemeral port, and keep state in memory or under a
   per-process temp path. Another agent may run the same suite on the same
   machine.

Ask of every test: could it pass while a real client still fails? A handler
called in-process skips auth and serialization. A response checked against the
server's own types proves nothing about a client built last month.

**Done:** each changed operation has named scenarios that pass, or a kept
failure that names the unmet assertion.

## 3. Crash, restart and overlap

Only for a change to durable state, idempotency, background work an operation
starts, startup, shutdown or health checks. These tests are slow compositions,
so the `test-audit` cost rules decide where they live: share one subprocess
across cases where the cases allow it, and put a long run in the repository's
slow or release tier, not the default lane.

1. Run the server as a subprocess with an ephemeral port, on the real store
   engine with its own on-disk state directory or uniquely named database. A
   fake or in-memory store survives a restart of anything and proves nothing
   about durability. Wait on the readiness endpoint, never on a sleep.
2. Kill it without a graceful shutdown while a write is in flight. Hold the
   write there deterministically: make the fake of an outside dependency the
   write waits on block, then kill. Never land in the window with a sleep or
   a timer, and never add a fault hook to production code for the test. When
   the write waits on nothing outside the process, kill between requests and
   report the in-flight window as unproven.

   Restart on the same state. Assert that acknowledged writes are present and
   that interrupted work is resumed or reported failed, never silently lost.
   Then retry the unacknowledged write and assert what the contract promises:
   with an idempotency key, or for an operation that is idempotent by
   definition, it applies exactly once. For an operation with no such
   guarantee, do not assert exactly once. Report that a retry can apply it
   twice.
3. Check that readiness reports not ready while the server cannot do work:
   starting, draining, or a required dependency down.
4. When a stored or wire format changed, run the previous version and the new
   version on the same state, then roll back to the previous version, and
   repeat the stage 2 success rows against each. When the repository cannot
   run its previous version, name that gap.
5. When instances hold exclusive ownership of work (a lease, a leader, a
   single-writer job), prove takeover and fencing separately on the same
   state. Replicas that share nothing but the store need neither: report the
   step as not applicable.
   - Takeover: kill the first instance and assert that a second one completes
     its work.
   - Fencing: the first instance must still be alive, so suspend it or cut it
     off from the store instead of killing it. Let the second take over,
     resume the first, and assert that its next write is refused. A killed
     process cannot write, so a kill proves nothing about fencing.

**Done:** each applicable case is recorded as passed, failed with what was lost
or duplicated, or not run with the reason.

## Live proof

Not a stage of this skill. Against a running install, use `validate-behavior`
(`${AGENT_KIT_HOME:-$HOME/.agents/agent-kit}/skills/validate-behavior/SKILL.md`)
with a behavior contract. It is read-only and source-blind.

## Pull Request gate

A Pull Request that changes the contract says in its body whether the change
is additive or breaking, and which version pairs were proven. A breaking change
with neither a new version nor an owner decision is a delivery blocker.

## Output

Report:

- the stages run and why the others were skipped;
- the contract source, and the drift check command and its result or the
  recorded example exchanges;
- additive or breaking, with the version pairs proven and those not run;
- test commands and results, with scenario names;
- crash, restart and overlap results;
- what the mocks cannot prove; and
- untested operations and the reason.
