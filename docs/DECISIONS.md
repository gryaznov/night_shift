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
