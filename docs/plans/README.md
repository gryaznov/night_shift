# Plans

One file per unit of work: `NNNN-slug.md`, zero-padded, sequential, never
renumbered and never deleted. A completed plan stays. An abandoned plan stays,
marked abandoned with the reason — that record is what stops the idea coming
back next quarter.

## Authorship

`## Intent`, `## Acceptance criteria`, `## Out of scope` are written by me,
before any session opens. Nothing else may draft them, including as a "starting
point to react to". Everything below them is Claude's.

## Template

```
NNNN — <title>

Status: draft | active | done | abandoned
Brief: docs/briefs/NNNN-<slug>.md (or: none)

Intent [human]

<The problem, in business terms. Why this is worth doing now. Two paragraphs
maximum.>

Acceptance criteria [human]

<Numbered. Each one observable and testable by someone who cannot see the
code. "Fast" is not a criterion; "responds within 200ms at 1000 rows" is.>

Out of scope [human]

<What this explicitly does not do. This section prevents more damage than any other.>

Implementation plan [claude]
Steps [claude]
 1.
 2.
Notes / deviations [claude]
```

## Rules

- A step must be independently committable and independently verifiable. If it
  isn't, it is too large.
- Steps are checked off as their commits land, so a fresh session can resume
  from the file alone.
- A criterion that turns out to be ambiguous is fixed in this file, by me,
  before implementation continues. It is never resolved inside a session.
