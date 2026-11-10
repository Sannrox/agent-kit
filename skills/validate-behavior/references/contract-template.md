# Behavior contract template

Use this shape when no contract exists. Keep it short enough that a
source-blind validator can run it without implementation notes.

```md
# Behavior contract

## Goal
<What must be true from the user's point of view.>

## Target
- Type: web app | CLI | API | generated artifact | other
- Access: <URL, command, endpoint, artifact path, or setup command>
- Fixtures and credential source: <fixtures, plus environment variable or
  secret-tool names; never values>

## User tasks
1. <Concrete task a real user or operator performs.>

## Expected behavior
- <Screen, CLI output, API response, file content, state change, or
  persistence rule.>
- <Failure behavior for invalid input or unavailable data.>

## Anti-cheat probes
- <Change input data and check the output changes accordingly.>
- <Refresh, retry, or restart and check persistence or reset.>
- <Empty, invalid, or boundary input and the promised handling.>

## Evidence
- <Terminal excerpts, response snippets, screenshots, file summaries.>

## Out of scope
- <What the validator must not judge.>
```

**Done when:** every task and probe has an expected observable result and an
evidence type.
