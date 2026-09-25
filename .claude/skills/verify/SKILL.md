---
description: Runs the project verification suite and reports real output.
disable-model-invocation: false
---

Run each command in order. Stop at the first failure and report it.

!`mix compile --warnings-as-errors`
!`mix format --check-formatted`
!`mix sobelow --exit`
!`mix test 2>&1 | tail -30`

Report actual output. Never summarize a command that did not run.
