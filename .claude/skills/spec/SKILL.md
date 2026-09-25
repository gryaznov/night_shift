---
description: Creates or advances a plan file. Scaffolds the human-owned sections, then later writes the implementation plan against them.
disable-model-invocation: true
argument-hint: <slug or plan-number>
---

Plan file for: $ARGUMENTS

## Mode 1 — the plan file does not exist

Create `docs/plans/NNNN-<slug>.md`, numbered one above the highest existing
plan, containing the skeleton from `docs/plans/README.md` with the
human-owned sections empty.

Then **stop**. Do not draft intent. Do not draft acceptance criteria. Do not
suggest what they might contain. Those sections are mine, and anything you put
there — including a "rough draft to react to" — anchors what I write and
reintroduces the circularity this whole structure exists to prevent.

Tell me the file path and stop.

## Mode 2 — the plan file exists with its human sections filled

Read `## Intent`, `## Acceptance criteria`, and `## Out of scope`. Read the
project invariants and any relevant domain docs. Read the linked brief if
there is one.

Then, without editing any source file:

1. Restate each acceptance criterion in your own words. If your restatement
   differs from mine, that is a specification defect — raise it before
   planning further.
2. Identify every criterion that is ambiguous, untestable as written, or
   silently assumes something not stated. List them. Do not resolve them.
3. Distinguish two kinds of unknown. An **ambiguity in my criteria** — where the
   spec admits two readings — you list and do not resolve. A **fact about the
   codebase** you go and establish, then state with evidence. Never present a
   question the source answers as something for me to rule on; read the file
   instead.
4. Produce `## Implementation plan`: the approach, the modules and files
   involved, the data changes, the risks.
5. If more than one approach is viable, describe each and rank by simplicity.
   Recommend one and say what would change the recommendation.
6. Produce `## Steps`: an ordered checklist, each step independently
   committable and independently verifiable. A step that cannot be verified on
   its own is too large — split it.
7. Steps must separate test authoring from implementation. Tests are written in a
   separate session by `spec-tester`, from the acceptance criteria alone. An
   implementation step must not add, extend, or assert in a test file — no
   exceptions, however small. Deleting an obsolete comment is allowed; adding an
   assertion is not.

Flag any step that touches an invariant, a permission boundary, a migration,
or money. Those get full review later regardless of size.

Write both sections into the plan file. Change nothing above them.
