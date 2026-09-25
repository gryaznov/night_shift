# Decisions

Append only. Never remove or rewrite an entry — supersede it with a new one
that references it. Each entry: the decision, the rejected alternative, the
reason. One paragraph.

Claude drafts these at wrap; I edit before commit.

---

## 0001 — Schema-per-tenant via Triplex

Tenant data lives in one Postgres schema per tenant. Rejected: shared tables
with `org_id` on every row. Reason: a missing prefix fails closed — the table
does not exist in `public` — while a missing `org_id` filter leaks silently.
Isolation is structural rather than remembered. Accepted cost: migrations run
once per tenant and catalog size grows with tenant count; revisit when
migration time becomes a deploy problem or cross-tenant reporting is required.

## 0002 — Tenant is the business, not the site

A tenant is a hospitality business; its sites live inside its schema.
Rejected: one tenant per site. Reason: head-office announcements and staff
working across sites are core use cases, and per-site tenants would make both
cross-schema queries.

## 0003 — Users in public, members per tenant

Login identity (`users`) lives in `public`; employment (`members`: role, site,
active) lives in the tenant schema. Rejected: users inside tenant schemas.
Reason: one person can work for several businesses with one login, and
deactivation must end one employment without touching the others.

## 0004 — Derived group membership (unverified assumption)

Site and role groups compute their members from site and role; managers do not
edit them. Rejected: manually managed groups, as in WhatsApp. Reason: manual
membership drifting from reality — leavers retaining access, new hires missed
— is assumed to be the core pain. This is an inference, not verified with an
operator. Question for a practitioner: should site and role groups be
automatic and exhaustive, or do managers curate them?

## 0005 — `members` lives in `public`, superseding 0003

`members` is a `public` table keyed by `user_id` and `tenant_id`, not a
per-tenant table; 0003's "employment lives in the tenant schema" is superseded,
while its ruling that `users` stays in `public` stands. Rejected: a member row
inside each tenant schema (resolving a session would then scan every schema, and
a user holding two jobs could not be resolved in one query), and a link-only
table in `public` pointing at per-tenant employment rows (two writes, two places
for `active` to disagree). Reason: authorization is one indexed query on
`public.members`, and it fails closed — no prefix is involved, so no prefix can
be forgotten. Cost: tenant isolation for this one table is a `tenant_id` filter
rather than structural, which invariant 2 makes explicit; the session-resolution
query (`Members.list_active_members/1`) filters on the authenticated `user_id`
instead, since its question is which tenants the user may act in at all, and
invariant 2 names that carve-out.

## 0006 — `NightShift.Accounts` is login, `NightShift.Tenants` is provisioning — DRAFT

`mix phx.gen.auth` was generated into `NightShift.Tenants`; that context was
renamed to `NightShift.Accounts` and `NightShift.Tenants` now owns tenant
records and Triplex provisioning. Rejected: leaving authentication in
`Tenants` and naming provisioning something else (`Businesses`, `Orgs`).
Reason: the table is `tenants`, the schema is `Tenants.Tenant` and Triplex's
whole vocabulary is "tenant", so any other owner of that word reads as a
second concept. The rename touched only generated code and generated tests.

## 0007 — `members.site_id` has no foreign key — DRAFT

`members` is in `public` and `sites` is in each tenant schema, so `site_id` is
a plain NOT NULL `:binary_id` validated by `Members.create_member/2` against
that tenant's `sites`. Rejected: moving `sites` into `public` to buy a real
foreign key. Reason: site names are one business's data, which is the part of
invariant 1 worth keeping; no single FK can span per-tenant schemas anyway.
Cost: a site deleted from a tenant schema would orphan member rows silently,
and nothing but `create_member/2` keeps the two in step. Proposed check: a
test that `create_member/2` rejects another tenant's `site_id` (present), and
a deletion path for `sites` must re-check this when 0002+ adds one.

## 0008 — Identity is resolved once; `active` is re-read where it is acted on — DRAFT

The tenant and the acting member are resolved once in `on_mount`, but every
`Members` function that authorizes re-reads the target member's `active` flag
(`still_active/1`) before deciding. Rejected: trusting the `active` value on
the member struct carried in the socket. Reason: invariant 3 fixes *identity*
and forbids re-deriving it; invariant 4 forbids a deactivated member reading
or posting "from that moment, including sessions already open", which a stale
flag in a long-lived socket assign cannot honour. Invariant 3 now says so
explicitly.

## 0009 — `create_site/2` and `create_member/2` take a tenant, not an acting member — DRAFT

These two `Members` functions break the "acting member first" shape of
invariant 5. Rejected: threading a synthetic or nil actor through them to keep
the signature uniform. Reason: nothing in the product creates a site or a
member — they exist for seeds and fixtures, so there is no actor whose
permission could be decided, and a nil actor would make the first argument
meaningless exactly where authorization is supposed to live. When member
creation gains a UI, it gets an actor-first function and these become private
or seed-only.

## 0010 — Deactivation kills open sockets from one attached hook — DRAFT

`Members.deactivate_member/2` broadcasts on `Tenancy.topic(tenant, :members)`
after its transaction commits, and `TenantAuth` handles that message in an
`attach_hook`, terminating the LiveView. Rejected: redirecting instead of
terminating (an already-rendered page keeps its tenant data on screen and its
assigns in memory), and handling the message in each tenant LiveView (one
omission reopens the hole for one page). Reason: criterion 5 and invariant 4
require the session to end, and a hook in the `live_session`'s `on_mount`
cannot be forgotten by a new LiveView. Broadcasting after commit, never
inside the transaction, keeps a rolled-back deactivation from disconnecting
anyone.

## 0011 — Two persistent test tenants, provisioned before ExUnit starts — DRAFT

`NightShift.TenantSetup.run!/0` find-or-creates two fixed tenants
(`tenant_one`, `tenant_two`), migrates both, and asserts their schemas exist —
all before `ExUnit.start/0` and `Sandbox.mode(:manual)`. Schemas persist
between runs. Rejected: creating a tenant per test or per suite run. Reason:
schema DDL commits on an unsandboxed connection and would otherwise be rolled
back with the test that triggered it, and running every Triplex migration per
test costs the whole suite's runtime for no isolation gain — two tenants are
enough because isolation tests need exactly "mine" and "another". `tenant_two`
is what `tenant_fixture(:two)` hands out. The setup lives in a compiled module
rather than inline in `test_helper.exs` so that Triplex 1.3.0's deprecated
`repo.__adapter__` call warns once at compile time instead of on every run.
