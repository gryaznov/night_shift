---
description: Executes exactly one step of a plan file, verifies it, and stops.
disable-model-invocation: true
argument-hint: <plan-number> <step-number>
---

Plan $1, step $2.

Read `docs/plans/$1-*.md`. Read only the step named. Read the plan's
`## Acceptance criteria` and the project invariants.

## Rules

- Implement **only** this step. Not the next one, not an obvious adjacent fix,
  not a cleanup you noticed on the way. If you find something else worth
  doing, add one line to the plan's `## Notes` and continue.
- If the step turns out to be larger than the plan described, stop and say so
  before writing code. Do not absorb the surprise silently.
- Verify with `/verify`. The full suite is allowed in this repo. Show actual
  output; never summarize a command you did not run.
- If verification fails, fix the cause. Do not weaken a test, loosen an
  assertion, or narrow a check to go green.
- If the step is tagged `[migration]`, `[permission boundary]` or
  `[invariant]`, say so at the top of your report.
- Pipe any command that can produce more than ~50 lines through `tail -30` or
  `grep -E "^\s+[0-9]+\) test|tests,.*failures"`. Show the summary and the
  failure list, never the full run.
- Read a file once per session. If you have already read it, work from what you
  have; re-read only if you changed it or a tool reported it changed.
- Report in short prose bullets. No tables of changed files, no criterion
  matrices, no restating the plan back to me. I have the plan; tell me what
  happened and what is at risk.
- Run each verification command on its own line. Do not chain with `&&`, `;` or
  pipes — the permission system matches the entire command string, so a compound
  command never matches an allowed pattern and always prompts. If you need the
  exit code, run the command plainly and report what it printed.
- For commands that can produce more than ~50 lines, pipe through `tail -30`.
  Accept the permission prompt in that case — do not add `; echo "EXIT:$?"` or
  chain further commands to avoid it.

When a step is tagged `[spec-tester, fresh session]`, dispatch it with:
- the plan's ## Intent, ## Acceptance criteria and ## Out of scope, plus the
  step's own text — nothing below those sections;
- an explicit read list: @spec, heads and moduledocs of the service modules under
  test, schema and value modules in full, everything else barred, with the reason;
- whether feature tests are required, and that it must name the command rather
  than run them;
- run only the non-feature files it creates; never bare `mix test`;
- do not review or modify its work; report verbatim.

The read carve-out is honour-based — the Read tool returns whole files — so state
it and rely on the disclosure.

## When done

- Mark the step complete in the plan file.
- Update `## Notes` if the implementation deviated from the plan, with the
  reason.
- State plainly what is not covered, what you left unverified, and any risk
  you noticed.

Then stop. Do not begin the next step.
