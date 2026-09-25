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
