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
- Choosing between tenants. Seeds give each user one membership. No two memberships in two different tenants for the same user should exist.
- Tenant sign-up, invitations, member creation UI. Members come from seeds.
- Reactivation, role changes via UI, head-office roles above site level.
- Password reset, SSO, magic links.
