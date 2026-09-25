# NightShift

Internal communications for hospitality businesses, replacing WhatsApp groups
on personal phones. As of plan 0001 it carries the foundation only: each
business is an isolated tenant, a person reaches one solely through a member
record naming their site, team and role, and a manager can end that access
instantly — including any page the member already has open. Chat and
announcements have routes reserved but no behaviour yet.

## Run it

`mix.exs` requires Elixir ~> 1.14; developed on 1.17.2 / Erlang OTP 26. Needs
PostgreSQL on `localhost` with the `postgres`/`postgres` credentials from
`config/dev.exs`.

    mix setup          # deps, database, migrations, seeds, assets
    mix phx.server     # http://localhost:4000

`mix setup` runs `priv/repo/seeds.exs`, which creates two businesses with two
sites each — one manager and six staff per business — and prints every
sign-in address at the end. The password for all of them is `nightshift123!`;
`manager@north-coast.test` is a manager. Re-run seeds with
`mix run priv/repo/seeds.exs`, or rebuild from scratch with `mix ecto.reset`.

There is no sign-up, invitation or password reset: members come from seeds.

## Test it

    mix test                          # whole suite
    mix test test/night_shift/members_test.exs

The `test` alias creates and migrates the test database. Tenant schemas are
DDL and cannot live inside the test sandbox, so `test/test_helper.exs`
provisions two fixed tenants (`tenant_one`, `tenant_two`) before ExUnit starts
and leaves them in place between runs; tests reach them through
`tenant_fixture/0` and `tenant_fixture(:two)`. Dropping the test database is
safe — the next run rebuilds both.

Static checks, as run before closing a plan:

    mix compile --warnings-as-errors
    mix format --check-formatted
    mix sobelow -i Config.HTTPS,Config.CSP --skip --exit

## Where things are

    lib/night_shift/            contexts — business rules and authorization
    lib/night_shift_web/        LiveViews and components — render and dispatch
    priv/repo/migrations/       public schema (users, tenants, members)
    priv/repo/tenant_migrations per-tenant schema (sites)
    docs/                       DECISIONS.md, CHANGELOG.md, plans/

`.claude/rules/invariants.md` holds the rules that govern tenant isolation and
authorization; read it before changing either.
