# Invariants

Rules only. If a situation requires exception and/or violate any of these rules - write that into docs/DECISIONS.md.

1. Tenant data lives only in tenant schemas. `public` schema holds only tenants, users
   and auth tokens. No table name exists in both. No tenant's data can live in `public`.
2. Every tenant query sets `prefix:` through the single tenancy helper. A prefix
   is never built from params, paths or client events.
3. The tenant and acting member are resolved once, in `on_mount` or a plug, from
   the authenticated session. Nothing downstream re-derives or changes them.
4. A user cannot act in a tenant in any way except for an active membership. A
   deactivated member can neither read nor post from that moment, including
   sessions already open.
5. Authorization lives in context functions, which take the acting member as
   their first argument. LiveViews never decide permissions.
6. PubSub topics include the tenant. No broadcast crosses tenants.
7. Membership of site and role groups is derived, never written directly.
8. Messages and acknowledgements are never hard-deleted from the system.
9. Tenant tables change only via tenant migrations (`triplex`); public tables only via
   repo migrations (`ecto`).
