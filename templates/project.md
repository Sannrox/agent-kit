# Project profile for agent-kit skills

<!-- Read by the shared skills in https://github.com/Sannrox/agent-kit. Keep repo-specific facts here, not in the shared skills. Section headings are a contract: do not rename them. -->

## Project

- Name: example
- Feature means: a new observable user or integration outcome

## Ownership boundaries

What this repository owns and what it never decides.

Route work owned by another repository (list the owners) to that repository.

## Affected areas

area-a/area-b/security

## Shared surfaces

Issues touching the same shared surface run in sequence, never as parallel lanes:
the public API and the persisted data format.

## Impact boundaries

- the boundaries a change must be traced across;

## Compatibility and failure obligations

Version pins, partial failures, and data formats a change must stay compatible with.

## Evidence map

The test kinds that prove each risk.

## Verification matrix

| Surface | Required evidence |
| --- | --- |
| example surface | the evidence required |

## Release audit

- items to audit before a release;
