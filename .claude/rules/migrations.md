---
paths:
  - "priv/repo/migrations/**"
  - "priv/repo/tenant_migrations/**"
---

# Migrations

- `priv/repo/migrations/` — public schema only: tenants, users, users_tokens.
- `priv/repo/tenant_migrations/` — everything else. Runs once per tenant.
- A tenant table referencing a public table sets `prefix: "public"` on the
  reference. Public tables never reference tenant tables.
- Until plan 0001 is marked done, migrations may be edited in place and the
  database reset. After that, never edit a migration; add a new one.
- Destructive operations — drop, truncate, destructive type change — are never
  written without asking first.
- Every tenant migration must succeed on a freshly created tenant.
