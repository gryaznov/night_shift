# 0001 — Foundation: tenants, members, access

Status: draft
Brief: none

## Intent

Currently, hospitality staff coordinate in WhatsApp groups on personal phone numbers. This is hard for the business to control who is in them: ex-employees are still having access to the chats, new employees are
added late or are forgotten to be added, and managers carry dozens of staff numbers on their own phones.

This plan establishes the base for every feature: each business is an isolated tenant, a person belongs to it only through a member record with a site, a team and a role, and a manager can establish or end that access instantly.

## Acceptance criteria

1. A user with an active membership record in a tenant signs in and sees only that tenant's workspace. A user with no active membership record cannot access the tenant's data in any way (e.g. signs in and sees a "no access" page and no tenant data).
2. No context function called by a member of tenant A returns or changes data belonging to tenant B. Never.
3. Every member has exactly one site, one team (kitchen, front of house, bar) and one role (manager, staff). A member without any of these is rejected.
4. A manager can deactivate a member of their own tenant and never another tenant's staff. A staff member never can deactivate anyone.
5. When a member is deactivated, their open LiveView sessions in that tenant are disconnected, and their next request is shown the "no access" page.
6. Running seeds on an empty database creates two tenants, each with two sites, one manager and at least four staff across all teams, with documented sign-in credentials.
7. The test suite also has two tenants pre-created before each run in a `test_helper`, so the suite has not to waste time on running all triplex migrations before each test separately.

## Out of scope

- Chat and announcements. This plan only reserves their routes and navigation entries.
- Choosing between tenants. `members` supports a user holding several memberships, with a different role in each, but 0001 ships no tenant chooser: seeds give each user exactly one membership, and behaviour with more than one is undefined until a later plan.
- Tenant sign-up, invitations, member creation UI. Members come from seeds.
- Reactivation, role changes via UI, head-office roles above site level.
- Password reset, SSO, magic links.

## Implementation plan

### Naming correction first

`mix phx.gen.auth` was run into a context named `NightShift.Tenants`
(`lib/night_shift/tenants.ex:1`, schemas `lib/night_shift/tenants/user.ex`,
`user_token.ex`, `user_notifier.ex`, fixtures `NightShift.TenantsFixtures`).
That name is needed for tenant provisioning. Rename the generated context to
`NightShift.Accounts` before anything else; it is mechanical and touches only
generated code and generated tests.

### Triplex configuration

On Postgres, Triplex derives the tenant list from `information_schema.schemata`
and ignores `tenant_table` (`deps/triplex/lib/triplex.ex:280,308`), so:

- `reserved_tenants` must be set to exclude `public`, `information_schema` and
  `~r/^pg_/`; it defaults to `[]`, which would report those as tenants.
- `tenant_field: :schema`, so a `%Tenant{}` reaching `Triplex.to_prefix/1`
  resolves to its schema name rather than its `:id`. A belt only — prefixes
  reach Triplex through `NightShift.Tenancy`, never as a bare struct.
- `Tenants.list_tenants/0` reads the `tenants` table. `Triplex.all/0` is used
  only where a physical schema list is wanted, and never for authorization.

### Members live in `public`

`members` is a public table: `user_id`, `tenant_id`, `role`, `site_id`, `team`,
`active`, `deactivated_at`. Authorization is then one indexed query on
`public.members` — no scan across tenant schemas, and a user may hold several
memberships at once, staff in one tenant and manager in another.

Consequences, in order of weight:

1. **This supersedes DECISIONS 0003 and is an exception to invariant 1.** That
   decision put employment — role, site, active — in the tenant schema; this
   plan puts it in `public`. Invariant 1 says `public` holds only tenants,
   users and auth tokens. Both need a DECISIONS entry at wrap; invariant 1
   itself needs amending, not just excepting.
2. **Membership queries lose structural isolation.** DECISIONS 0001 chose
   schema-per-tenant because a forgotten prefix fails closed while a forgotten
   `org_id` filter leaks silently. Membership queries now have exactly that
   failure mode. Mitigation: every read of `members` goes through
   `NightShift.Members`, `tenant_id` is a required non-defaulted argument on
   each such function, and the isolation tests cover the cross-tenant case.
   Message and announcement data keeps the structural guarantee.
3. **`site_id` gets no foreign key.** `sites` stays in the tenant schema, so a
   public column cannot reference it — `.claude/rules/migrations.md` forbids
   public tables referencing tenant tables, and no single FK can span per-tenant
   schemas. `site_id` is a plain `:binary_id`, NOT NULL, validated by
   `Members.create_member/2` against that tenant's `sites`.

Rejected: moving `sites` into `public` as well, which would buy a real foreign
key. Site names are plainly one business's data, and that is the part of
invariant 1 worth keeping. Rejected: a link-only public table with role and
site left in the tenant schema — it splits one employment across two schemas
and makes criterion 3 unenforceable in either.

After this, the tenant schema in 0001 holds `sites` and nothing else. The
message and acknowledgement tables of 0002 and 0003 are what the per-tenant
schemas are actually for.

### Modules

    NightShift.Accounts              public users, auth (renamed from Tenants)
    NightShift.Tenants               tenant records, provisioning via Triplex
    NightShift.Tenants.Tenant        public `tenants` schema: name, schema
    NightShift.Tenancy               the single prefix/topic helper (inv. 2, 6)
                                     prefix/1 takes %Tenant{} -> tenant.schema
    NightShift.Members               members and sites, authorization
    NightShift.Members.Member        public `members` schema
    NightShift.Members.Site          tenant `sites` schema
    NightShiftWeb.TenantAuth         on_mount/plug: :tenant, :current_member
    NightShiftWeb.NoAccessLive       the "no access" page
    NightShiftWeb.WorkspaceLive      workspace landing + reserved nav

### Data changes

Public (`priv/repo/migrations/`):

- `tenants` — one row per company: `name` (the business name) and `schema` (its
  Postgres schema name, unique, validated `^[a-z][a-z0-9_]*$` because it
  becomes a DDL identifier), timestamps. On Postgres, Triplex never reads this
  table, so its shape is ours alone.
- `members` — `user_id` → `users`, `tenant_id` → `tenants`, `site_id`
  (`:binary_id`, NOT NULL, no FK), `team` and `role` NOT NULL with check
  constraints matching their `Ecto.Enum` values, `active` boolean NOT NULL
  default true, `deactivated_at`. Unique index on `(user_id, tenant_id)` — one
  employment per user per tenant, several tenants per user. Index on
  `(tenant_id, active)`. Never hard-deleted.

Tenant (`priv/repo/tenant_migrations/`, new directory):

- `sites` — `name`, timestamps.

### Test harness

`test/test_helper.exs`, in this order:

1. Two fixed tenants, find-or-create by `schema` (`"tenant_one"`,
   `"tenant_two"`): `Tenants.get_tenant_by_schema/1`, and on `nil`
   `Tenants.create_tenant/1`. Schemas persist between runs, so the second run
   creates nothing.
2. `Triplex.migrate/2` for each, unconditionally. It runs `:up, all: true`, so
   it is idempotent on an existing schema and a tenant migration added later
   is picked up without dropping the test database.
3. Assert each schema is in `Triplex.all(NightShift.Repo)` — which is why
   `reserved_tenants` must be configured, or `public` and the `pg_*` schemas
   appear in that list.
4. `ExUnit.start()`.
5. `Ecto.Adapters.SQL.Sandbox.mode(NightShift.Repo, :manual)`.

Steps 1–3 must precede 4 and 5: schema DDL has to commit on an unsandboxed
connection, or it is rolled back with the test that triggered it.

`tenant_fixture/0` returns one of the two fixed tenants; `tenant_fixture/1`
takes `:two` for the isolation tests. Neither provisions a schema.
`.claude/rules/testing.md` says a tenant is created by `tenant_fixture/0` —
that stays true, the implementation changes; the rule text is updated at wrap.

No schema pool: `.claude/rules/testing.md` requires `async: false` for tests
touching tenant schemas, so one schema per tenant suffices.

### Risks

- `mix test` alias runs `ecto.create`/`ecto.migrate` only; tenant migrations
  are driven from `test_helper.exs`, not the alias, so a fresh checkout works.
- Tenant creation in `test_helper.exs` runs against the real database with no
  sandbox, so a crash there leaves partial schemas behind. `create_tenant/1`
  must clean up its own schema on a failed migration.
- Generated registration, password-reset and confirmation routes contradict
  `## Out of scope`. Removing them deletes generated tests — an explicit step,
  awaiting a ruling.
- Criterion 5's disconnect uses `live_socket_id` from `UserAuth`
  (`"users_sessions:<token>"`), which is per user, not per tenant.

## Steps

1. [x] Rename `NightShift.Tenants` → `NightShift.Accounts` (context, schemas,
   notifier, `NightShift.AccountsFixtures`, generated tests, `UserAuth`
   alias). No behaviour change. Verify: `/verify` green.
1b. [x] Unblock `/verify`: format the four generated files the LiveView 1.0
   formatter rejects, add a Content-Security-Policy to the `:browser` pipeline
   and `force_ssl: [hsts: true]` to `config/prod.exs`. Verify: all four
   `/verify` commands. **FLAG: touches security headers.**
2. [x] Public migration: `tenants` (`name`, `schema`) and `members` as
   specified; `Tenants.Tenant` schema with the `schema` format validation;
   `reserved_tenants` and `tenant_field: :schema` in `config/config.exs`.
   Verify: `mix ecto.reset`, table shape and indexes from `psql \d`.
   **FLAG: migration, invariant 1 exception, supersedes DECISIONS 0003.**
3. [x] `NightShift.Tenancy` — `prefix/1` (`%Tenant{}` -> `schema`), `topic/2`,
   `@moduledoc`, `@spec`,
   raising stubs. Verify: compiles; every call raises.
   **FLAG: invariants 2 and 6.**
4. [ ] Tenant migrations: `priv/repo/tenant_migrations/` with `sites`. Verify:
   provision a scratch tenant, inspect the table, drop it.
   **FLAG: migration, invariant 9.**
5. [ ] Contract step: `@moduledoc`, `@spec` and raising stubs for
   `NightShift.Tenants` (`create_tenant/1`,
   `get_tenant_by_schema/1`, `list_tenants/0`) and `NightShift.Members`
   (`create_site/2`, `create_member/2`, `get_active_member/2`,
   `list_memberships/1`, `list_members/2`, `deactivate_member/2` — acting
   member first, `tenant_id` never defaulted). Verify:
   compiles; specs present; every function raises.
6. [ ] Test harness, no assertions: `test/test_helper.exs` per the harness
   section — find-or-create two tenants, `Triplex.migrate/2` each, assert both
   are in `Triplex.all/1`, all before `ExUnit.start()` and
   `Sandbox.mode(:manual)`; `test/support/fixtures/` gains `tenant_fixture/1`,
   `site_fixture/1`, `member_fixture/2`. Verify: `mix test` green on the
   existing suite from a dropped database and again from a warm one; show
   tenant migrations running once per run, not per test.
   **FLAG: criterion 7.**
7. [ ] `spec-tester`, fresh session: context and LiveView tests for criteria
   1–5 from the criteria alone, including the negative cases required by
   `.claude/rules/testing.md` — other tenant, other member, deactivated
   member, staff attempting deactivation. No implementation in this step.
8. [ ] Implement `NightShift.Tenants` provisioning: create the row, create the
   Triplex schema, run tenant migrations. Verify: spec-tester's tenant tests.
9. [ ] Implement `NightShift.Members`: sites in the tenant schema, members in
   `public`, `site_id` validated against the acting tenant's sites, criterion 3
   validations, and authorization in the context with the acting member first.
   Verify: spec-tester's member and isolation tests, including a read of
   tenant B's members with tenant A's member as actor.
   **FLAG: permission boundary, invariants 4 and 5, and the lost structural
   isolation named above.**
10. [ ] `NightShiftWeb.TenantAuth`: `on_mount :require_active_member`
    assigning `:tenant` and `:current_member` from the authenticated session
    only, matching plug for controllers, `NoAccessLive`, router
    `live_session`. Verify: spec-tester's access tests.
    **FLAG: permission boundary, invariants 3 and 4.**
11. [ ] Workspace shell: `WorkspaceLive`, `signed_in_path/1` pointed at it,
    stock Phoenix header in `app.html.heex` replaced with a mobile-first nav
    carrying `data-test-id`, reserved routes and stub LiveViews for chat and
    announcements. Verify: spec-tester's criterion 1 test.
12. [ ] Deactivation disconnect: broadcast on deactivate so open sockets
    re-mount and halt to the no-access page. Verify: spec-tester's criterion 5
    test. **FLAG: invariant 4, criterion 5.**
13. [ ] Seeds: two tenants, two sites each, one manager, at least four staff
    spanning teams, credentials documented. Verify: `mix ecto.reset` output;
    sign in as a seeded user. **FLAG: depends on the criterion 6 rulings.**
14. [ ] Remove out-of-scope auth surface: registration, password-reset and
    confirmation routes, LiveViews, their generated tests and the
    now-unused `Accounts` functions. Verify: `/verify` green; routes absent.
    **Awaiting ruling; blocks nothing above.**
15. [ ] Wrap: DECISIONS entries for the context rename, for public `members`
    superseding DECISIONS 0003, and for the test-tenant strategy; amend
    invariant 1 to admit `members`; update `.claude/rules/testing.md`; mark
    this plan done. **FLAG: edits an invariant.**

## Notes / deviations

- Step 1b was not in the original plan. `mix format --check-formatted` and
  `mix sobelow --exit` both failed at `488af8e`, on generated code, so no step
  in this plan could satisfy `## Done means` until they were fixed. The format
  failures were `<%= %>` interpolation the LiveView 1.0 formatter rewrites to
  `{}` in `core_components.ex` and the three generated templates.
- The CSP is not verified in a browser. `connect-src 'self'` covers the
  LiveView websocket only under CSP Level 3, `style-src` carries
  `'unsafe-inline'` because `Phoenix.LiveView.JS.show/hide` writes inline
  `display`, and `frame-src 'self'` in dev is for the live_reload iframe.
  LiveDashboard runs through the same pipeline. First real exercise is step 11,
  when the app is run.
