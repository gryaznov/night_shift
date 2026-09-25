---
description: Closes a work loop — verifies, records decisions, updates docs, and reports what remains.
disable-model-invocation: true
argument-hint: <plan-number>
---

Closing plan $ARGUMENTS.

## 1. Verify first

Run `/verify`. A loop does not close over a red suite.

## 2. Check the criteria

For each criterion: covered by which test, or not covered and why. One line
each, prose. No table. Any uncovered criterion is reported, not explained
away.

## 3. Draft decisions

For each choice made during this work that a future reader would otherwise
have to reverse-engineer, draft an entry for `DECISIONS.md`. Each entry
states the decision, the rejected alternative, and the reason. Skip anything
that is merely what happened — a decision entry earns its place only if
someone might later undo it for lack of context.

Mark the drafts clearly. I edit them before they are committed.

## 4. Report what remains

- Known defects introduced or discovered and not fixed.
- Anything deferred, and where it is recorded.
- Anything you were unable to verify.

Then stop.
