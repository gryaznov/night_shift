# NightShift

Internal communications for hospitality businesses: replaces WhatsApp for
staff 1-to-1, group and announcement messaging. Users are managers and
frontline staff, mostly on phones. Multi-tenant; one tenant per business.

@.claude/rules/invariants.md

## Verify

Run `/verify` before claiming any work complete. Show real output.

## Stack

- Elixir, Phoenix 1.7, LiveView
- PostgreSQL, Triplex — schema per tenant
- ExUnit, Phoenix.LiveViewTest

## Layout

    lib/night_shift/            contexts — all business rules and authorization
    lib/night_shift_web/        LiveViews and components — render and dispatch only
    priv/repo/migrations/       public schema
    priv/repo/tenant_migrations tenant schemas
    test/                       see .claude/rules/testing.md
    docs/                       plans, decisions

## Session start

Read `docs/DECISIONS.md`. If I named a plan, read `docs/plans/<N>-*.md` and
treat its `## Steps` as the active work. Otherwise my request is the task.

## Source of truth

On conflict the higher entry wins — flag it, name the governing source, wait.

1. My current instruction
2. `.claude/rules/invariants.md`
3. The active plan's `## Acceptance criteria`
4. `docs/DECISIONS.md`
5. `.claude/rules/*`
6. This file

## The loop

Plan (my intent and criteria) → implementation plan → contract step (context
modules with @moduledoc, @spec and raising stubs) → tests by spec-tester in
parallel with implementation → review → wrap.

## Take-home overrides

- Approving a plan's `## Steps` approves each step. I still review every diff.
- Full `mix test` is allowed.
- One model throughout; no model gate on flagged steps.

## Parallel sessions

Each parallel session runs in its own worktree (`./worktree new`), with its
own test database. Never run commands against another worktree.

## Scope

The active plan's `## Steps` and `## Out of scope` are locked. New requests
during implementation are scope creep until I say otherwise.

## Done means

- Every acceptance criterion is covered by a test, or the gap is stated.
- `/verify` passes, with output shown.
- Known failures and unresolved risks are stated, not omitted.
