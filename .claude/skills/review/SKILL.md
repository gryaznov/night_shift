---
description: Reviews the current uncommitted diff against the plan and invariants using a fresh-context reviewer.
disable-model-invocation: true
argument-hint: <plan-number>
---

## Diff under review

!`git diff HEAD`

## Files changed

!`git diff --stat HEAD`

## Untracked files (not in the diff above — read each one)

!`git status --porcelain --untracked-files=all | grep '^??'`

Delegate this review to the `code-reviewer` subagent. Give it: the diff above,
the path to the plan file (plan $ARGUMENTS if given, otherwise find the most
recently modified file in `docs/plans/`), and the project invariants path.

Do not review it yourself in this session — this session has seen the
implementation reasoning and would inherit its blind spots. That separation is
the entire value of the step.

Write the reviewer's findings to `REVIEW_RESULTS.md` as a todo list ordered by
severity, each item with a file, a line, and a concrete fix. Do not fix
anything. Do not edit any source file.

Then report the verdict line and stop.
