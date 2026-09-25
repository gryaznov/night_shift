---
paths:
  - "docs/**"
---

# Writing documentation in this repo

Documentation is read into a context window on every relevant session. Length
is expensive. Optimize for what a reader needs and nothing more.

## Always

- Prefer editing an existing document to creating a new one.
- Record the **rejected alternative and why**. A decision without its
  discarded options is unusable — the next reader re-litigates it.
- State constraints as rules, not as narrative. "Tenant data never lives in
  the shared schema", not "we decided that it would be better if".
- Name files, modules, and functions precisely. A doc that says "the auth
  layer" cannot be verified against code.

## Never

- Restate what `git log` already records. What changed goes in the changelog;
  documentation says what is true now.
- Duplicate a rule across two documents. Put it in one and reference it.
- Write a "Future improvements" or "Possible enhancements" section. Deferred
  work goes in a plan, a brief, or a bug file, where it has an owner.
- Add a document for a change small enough to be one line in an existing one.

## Length

- `.claude/rules/invariants.md`: 20 lines. Hard cap. If it grows, something in it is not an
  invariant - detect that and tell expliticly.
- A `DECISIONS.md` entry: one paragraph. Decision, rejected alternative, reason.
- A changelog entry: 10 lines.

## Invariants that can be tested must be tested

If you write a rule in prose that a grep, a compiler check, or a test could
enforce, say so explicitly and propose the check.
